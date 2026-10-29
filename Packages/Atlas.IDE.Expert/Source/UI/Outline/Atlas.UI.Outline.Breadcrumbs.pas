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
// - Rechts darf ein Kind-Steuerelement mit alRight stehen (Editorleiste
//   „in der Brotkrumenzeile“, #1101); die Glieder teilen sich dann nur die
//   Breite links davon (ContentRight).
// - WindowProblem und HitProblem nennen, warum Windows die Maus nicht an die
//   Leiste gibt (Bericht M2): Im atlas.log vom 21./22.10. bekam das Eltern-
//   fenster „EditorPanel“ die Klicks, obwohl die Leiste oben lag und kein
//   Geschwister darüber. Die Trefferprüfung von WindowFromPoint übergeht ein
//   Kindfenster nur, wenn es ausgeblendet oder gesperrt ist, der Punkt außer-
//   halb seiner Region liegt oder WM_NCHITTEST HTTRANSPARENT liefert; das
//   prüft HitProblem in dieser Reihenfolge, damit das Protokoll die Ursache
//   nennt statt einer Vermutung.
// - Höhe, Farben, Hervorhebung, Klick beim Loslassen, Kontextmenü (geht nie
//   an den Editor) und OnDisabled kommen vom Vorfahr TAtlasEditorBar (#1248).
//   Teile: Glied i ist i, das „›“ dahinter SeparatorPart + i.

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
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.UI.Editor.Bar;

type
  /// <summary>Menü zum Glied AIndex öffnen; APoint ist die linke untere Ecke des Glieds am Bildschirm.</summary>
  TAtlasCrumbMenuEvent = reference to procedure(AIndex: Integer; const APoint: TPoint);
  /// <summary>Zum Glied AIndex springen; ADeclaration = zur Deklaration statt zur Implementierung.</summary>
  TAtlasCrumbJumpEvent = reference to procedure(AIndex: Integer; ADeclaration: Boolean);

  TAtlasBreadcrumbBar = class(TAtlasEditorBar)
  private const
    /// <summary>Teil des „›“ hinter Glied i: SeparatorPart + i.</summary>
    SeparatorPart = $10000;
  private
    FCrumbs: TAtlasCrumbs;
    FRects: TArray<TRect>;
    /// <summary>„›“ hinter dem Glied; leer, wenn keins steht.</summary>
    FSeparators: TArray<TRect>;
    FFirstShown: Integer;
    FLaidOut: Boolean;
    FSelected: Integer;
    FEmptyText: string;
    FCrumbHint: string;
    FSeparatorHint: string;
    FOnOpenMenu: TAtlasCrumbMenuEvent;
    FOnOpenChildren: TAtlasCrumbMenuEvent;
    FOnJump: TAtlasCrumbJumpEvent;
    FOnLeave: TProc;
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
    /// <summary>Glied mit Menü oder Sprungziel (Hand, Hervorhebung)?</summary>
    function Clickable(AIndex: Integer): Boolean;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure AlignControls(AControl: TControl; var Rect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Rechter Rand der Glieder: Client-Breite ohne sichtbare Kinder mit alRight.</summary>
    function ContentRight: Integer;
    /// <summary>Glieder setzen; gleiche Glieder zeichnen nicht neu. Die Auswahl springt aufs letzte Glied.</summary>
    procedure SetCrumbs(const ACrumbs: TAtlasCrumbs);
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
    /// <summary>Was am Fenster der Leiste unabhängig vom Mauspunkt nicht stimmt (kein Fenster, anderer Thread,
    /// anderes Elternfenster, gesperrt, ausgeblendet); '' = in Ordnung.</summary>
    function WindowProblem: string;
    /// <summary>Warum die Trefferprüfung von Windows (WindowFromPoint) am Bildschirmpunkt nicht bei der Leiste
    /// ankommt, in ihrer Reihenfolge: WindowProblem, Punkt außerhalb des Fensters oder der Client-Fläche des
    /// Elternfensters, außerhalb der Fensterregion, durchlässiges Fenster, WM_NCHITTEST liefert HTTRANSPARENT,
    /// ein Geschwisterfenster liegt darüber. '' = Windows gäbe die Maus an die Leiste.</summary>
    function HitProblem(const AScreenPoint: TPoint): string;
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
  end;

implementation

uses
  System.Math,
  Vcl.Forms;

const
  Separator = '›';
  Ellipsis = '…';

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
  // csAcceptsControls: Kinder rechts (Editorleiste, #1101), mit WS_CLIPCHILDREN übermalt Paint sie nicht.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FSelected := -1;
end;

procedure TAtlasBreadcrumbBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  FLaidOut := False;
end;

procedure TAtlasBreadcrumbBar.SetCrumbs(const ACrumbs: TAtlasCrumbs);
begin
  if SameCrumbs(ACrumbs, FCrumbs) then
    Exit;
  FCrumbs := ACrumbs;
  FSelected := High(FCrumbs);
  SetHot(PartNone);
  FLaidOut := False;
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

function TAtlasBreadcrumbBar.ContentRight: Integer;
var
  Index: Integer;
  Child: TControl;
begin
  Result := ClientWidth;
  for Index := 0 to ControlCount - 1 do
  begin
    Child := Controls[Index];
    if Child.Visible and (Child.Align = alRight) then
      Result := Min(Result, Child.Left);
  end;
  Result := Max(0, Result);
end;

procedure TAtlasBreadcrumbBar.AlignControls(AControl: TControl; var Rect: TRect);
begin
  inherited AlignControls(AControl, Rect);
  // Ein Kind rechts kam, ging oder änderte die Breite: Glieder neu verteilen.
  FLaidOut := False;
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
  Index, Total, Available, Left_, Right_: Integer;
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
  Right_ := ContentRight;
  Available := Right_ - 2 * Scale(4);
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
      FRects[Index] := Rect(Left_, 0, Min(Left_ + Widths[Index], Right_), ClientHeight);
      Left_ := Left_ + Widths[Index];
      if (Index < High(FCrumbs)) or TrailingSeparator then
        FSeparators[Index] := Rect(Left_, 0, Min(Left_ + SeparatorWidth, Right_), ClientHeight);
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
  Canvas.Font.Color := ToColor(Colors.Muted);
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
  if Hot = SeparatorPart + AIndex then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.Pen.Color := ToColor(Colors.Selection);
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
  if ((Hot = AIndex) and Clickable(AIndex)) or ((AIndex = FSelected) and Focused) then
  begin
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.Pen.Color := ToColor(Colors.Selection);
    if Focused and (AIndex = FSelected) then
      Canvas.Pen.Color := ToColor(Colors.Accent);
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
    Canvas.Brush.Color := ToColor(Colors.Badges[Crumb.Badge.Kind].Background);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Radius := Scale(4);
    Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, Radius, Radius);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Height := -Round(Box.Height * 0.62);
    Canvas.Font.Color := ToColor(Colors.Badges[Crumb.Badge.Kind].Text);
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
    Canvas.Font.Color := ToColor(Colors.Text);
  end
  else
    Canvas.Font.Color := ToColor(Colors.Muted);
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
  PaintChrome(False);
  if Length(FCrumbs) = 0 then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
    Part := Rect(Scale(8), 0, ContentRight - Scale(4), ClientHeight);
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

function TAtlasBreadcrumbBar.Clickable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FCrumbs)) and
    ((Length(FCrumbs[AIndex].Siblings) > 0) or (FCrumbs[AIndex].Node >= 0));
end;

function TAtlasBreadcrumbBar.PartAt(X, Y: Integer): Integer;
var
  mIndex: Integer;
begin
  mIndex := SeparatorAt(X, Y);
  if mIndex >= 0 then
    Exit(SeparatorPart + mIndex);
  Result := CrumbAt(X, Y);
  if Result < 0 then
    Result := PartNone;
end;

function TAtlasBreadcrumbBar.PartHint(APart: Integer): string;
begin
  // Hinweis je Teil: Glied (Menü, Strg+Klick) oder „›“ (Kinder).
  if APart >= SeparatorPart then
    Result := FSeparatorHint
  else if Clickable(APart) then
    Result := FCrumbHint
  else
    Result := '';
end;

function TAtlasBreadcrumbBar.PartEnabled(APart: Integer): Boolean;
begin
  Result := (APart >= SeparatorPart) or Clickable(APart);
end;

procedure TAtlasBreadcrumbBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  // Erst beim Loslassen (Vorfahr): Beim Drücken holt die IDE den Fokus zurück in den Editor, das Menü ginge sofort
  // wieder zu.
  if APart >= SeparatorPart then
  begin
    OpenChildren(APart - SeparatorPart);
    Exit;
  end;
  Index := APart;
  if Index < 0 then
    Exit;
  FSelected := Index;
  Invalidate;
  // Ohne Geschwister gibt es kein Menü; dann springt auch der einfache Klick.
  if (ssCtrl in AShift) or (Length(FCrumbs[Index].Siblings) = 0) then
    Jump(Index, ssShift in AShift)
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

/// <summary>Klasse und, wenn es ein VCL-Steuerelement ist, dessen Name.</summary>
function WindowLabel(AWindow: HWND): string;
var
  WindowClass: array[0..255] of Char;
  Control: TWinControl;
begin
  WindowClass[0] := #0;
  GetClassName(AWindow, WindowClass, Length(WindowClass));
  Result := string(WindowClass);
  Control := FindControl(AWindow);
  if Control <> nil then
    Result := Result + ' ' + Control.Name;
end;

function TAtlasBreadcrumbBar.WindowProblem: string;
begin
  Result := '';
  if not HandleAllocated then
    Result := 'Leiste hat kein Fenster'
  else if GetWindowThreadProcessId(Handle, nil) <> MainThreadID then
    Result := 'Fenster gehört einem anderen Thread'
  else if (Parent = nil) or not Parent.HandleAllocated or (GetParent(Handle) <> Parent.Handle) then
    Result := 'Fenster hängt an einem anderen Elternfenster'
  else if not IsWindowEnabled(Handle) then
    Result := Format('Fenster ist gesperrt (Enabled %s)', [BoolToStr(Enabled, True)])
  else if GetWindowLongPtr(Handle, GWL_STYLE) and WS_VISIBLE = 0 then
    Result := 'Fenster ist ausgeblendet';
end;

function TAtlasBreadcrumbBar.HitProblem(const AScreenPoint: TPoint): string;
var
  Bounds: TRect;
  Region: HRGN;
  ExStyle: NativeInt;
  HitTest: LRESULT;
  Topmost: HWND;
begin
  Result := WindowProblem;
  if Result <> '' then
    Exit;
  GetWindowRect(Handle, Bounds);
  if not PtInRect(Bounds, AScreenPoint) then
  begin
    Result := Format('Punkt (%d, %d) liegt außerhalb des Fensters (%d, %d, %d, %d)', [AScreenPoint.X,
      AScreenPoint.Y, Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom]);
    Exit;
  end;
  // Kinder trifft Windows nur in der Client-Fläche des Elternfensters; im Rahmen bekommt es das Elternfenster.
  if not PtInRect(Parent.ClientRect, Parent.ScreenToClient(AScreenPoint)) then
    Exit('Punkt liegt im Rahmen des Elternfensters, nicht in seiner Client-Fläche');
  Region := CreateRectRgn(0, 0, 0, 0);
  try
    // Die Region ist relativ zur linken oberen Ecke des Fensters; ERROR = keine Region gesetzt.
    if (GetWindowRgn(Handle, Region) <> ERROR) and
      not PtInRegion(Region, AScreenPoint.X - Bounds.Left, AScreenPoint.Y - Bounds.Top) then
      Exit('Punkt liegt außerhalb der Fensterregion (SetWindowRgn)');
  finally
    DeleteObject(Region);
  end;
  ExStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);
  if ExStyle and WS_EX_TRANSPARENT <> 0 then
    Exit('Fenster hat WS_EX_TRANSPARENT');
  if ExStyle and WS_EX_LAYERED <> 0 then
    Exit('Fenster ist geschichtet (WS_EX_LAYERED)');
  // Über die ganze Fensterprozedur, also auch über Unterklassen und Stil-Hooks der IDE.
  HitTest := SendMessage(Handle, WM_NCHITTEST, 0, MakeLParam(Word(AScreenPoint.X), Word(AScreenPoint.Y)));
  if Integer(HitTest) = HTTRANSPARENT then
    Exit('WM_NCHITTEST liefert HTTRANSPARENT');
  Topmost := ChildWindowFromPointEx(Parent.Handle, Parent.ScreenToClient(AScreenPoint), CWP_SKIPINVISIBLE);
  if (Topmost <> 0) and (Topmost <> Handle) and (Topmost <> Parent.Handle) then
    Result := Format('Geschwisterfenster liegt darüber (%s)', [WindowLabel(Topmost)]);
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
