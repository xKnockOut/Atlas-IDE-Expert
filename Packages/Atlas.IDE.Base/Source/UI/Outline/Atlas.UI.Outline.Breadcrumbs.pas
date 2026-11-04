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

  /// <summary>Glieder der Brotkrumenleiste und ihre Aufteilung auf die Breite; Grundlage von
  /// TAtlasBreadcrumbBar.</summary>
  TAtlasBreadcrumbLayout = class(TAtlasEditorBar)
  private
    FCrumbs: TAtlasCrumbs;
    FRects: TArray<TRect>;
    /// <summary>„›“ hinter dem Glied; leer, wenn keins steht.</summary>
    FSeparators: TArray<TRect>;
    FFirstShown: Integer;
    FLaidOut: Boolean;
    FSelected: Integer;
    FEmptyText: string;
    function BadgeWidth: Integer;
    function CrumbWidth(AIndex: Integer): Integer;
    function SeparatorWidth: Integer;
    function EllipsisWidth: Integer;
    procedure Layout;
    /// <summary>Breite aller Glieder samt „›“; AWidths je Glied.</summary>
    function TotalWidth(out AWidths: TArray<Integer>): Integer;
    /// <summary>Flächen der gezeigten Glieder und ihrer „›“ ab FFirstShown, rechts bis ARight.</summary>
    procedure PlaceCrumbs(const AWidths: TArray<Integer>; ARight: Integer);
    function GetFirstShown: Integer;
    procedure SetEmptyText(const AValue: string);
    function TrailingSeparator: Boolean;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure AlignControls(AControl: TControl; var Rect: TRect); override;
  public
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
  end;

  TAtlasBreadcrumbBar = class(TAtlasBreadcrumbLayout)
  private const
    /// <summary>Teil des „›“ hinter Glied i: SeparatorPart + i.</summary>
    SeparatorPart = $10000;
  private
    FCrumbHint: string;
    FSeparatorHint: string;
    FOnOpenMenu: TAtlasCrumbMenuEvent;
    FOnOpenChildren: TAtlasCrumbMenuEvent;
    FOnJump: TAtlasCrumbJumpEvent;
    FOnLeave: TProc;
    procedure DrawCrumb(AIndex: Integer);
    /// <summary>Kennzeichen des Glieds ab ALeft; liefert den linken Rand des Namens dahinter.</summary>
    function DrawBadge(const ACrumb: TAtlasCrumb; ALeft: Integer): Integer;
    procedure DrawSeparator(ALeft: Integer; const AText: string); overload;
    procedure DrawSeparator(AIndex: Integer); overload;
    /// <summary>Glied mit Menü oder Sprungziel (Hand, Hervorhebung)?</summary>
    function Clickable(AIndex: Integer): Boolean;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Fokus und Auswahl aufs letzte Glied (Tastenkürzel).</summary>
    procedure FocusLast;
    /// <summary>Menü des Glieds öffnen, wenn es Geschwister hat.</summary>
    procedure OpenMenu(AIndex: Integer);
    /// <summary>Menü der Kinder des Glieds unter dessen „›“ öffnen, wenn es Kinder hat.</summary>
    procedure OpenChildren(AIndex: Integer);
    /// <summary>Zum Glied springen (OnJump), wenn es einen Knoten hat oder die Unit ist.</summary>
    procedure Jump(AIndex: Integer; ADeclaration: Boolean);
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

procedure TAtlasBreadcrumbLayout.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  FLaidOut := False;
end;

procedure TAtlasBreadcrumbLayout.SetCrumbs(const ACrumbs: TAtlasCrumbs);
begin
  if SameCrumbs(ACrumbs, FCrumbs) then
  begin
    Exit;
  end;
  FCrumbs := ACrumbs;
  FSelected := High(FCrumbs);
  SetHot(PartNone);
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasBreadcrumbLayout.SetEmptyText(const AValue: string);
begin
  if AValue = FEmptyText then
  begin
    Exit;
  end;
  FEmptyText := AValue;
  if Length(FCrumbs) = 0 then
  begin
    Invalidate;
  end;
end;

function TAtlasBreadcrumbLayout.ContentRight: Integer;
var
  Index: Integer;
  Child: TControl;
begin
  Result := ClientWidth;
  for Index := 0 to ControlCount - 1 do
  begin
    Child := Controls[Index];
    if Child.Visible and (Child.Align = alRight) then
    begin
      Result := Min(Result, Child.Left);
    end;
  end;
  Result := Max(0, Result);
end;

procedure TAtlasBreadcrumbLayout.AlignControls(AControl: TControl; var Rect: TRect);
begin
  inherited AlignControls(AControl, Rect);
  // Ein Kind rechts kam, ging oder änderte die Breite: Glieder neu verteilen.
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasBreadcrumbLayout.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasBreadcrumbLayout.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

function TAtlasBreadcrumbLayout.BadgeWidth: Integer;
begin
  Result := Scale(22);
end;

function TAtlasBreadcrumbLayout.SeparatorWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextWidth(Separator) + Scale(10);
end;

function TAtlasBreadcrumbLayout.EllipsisWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextWidth(Ellipsis) + Scale(6);
end;

function TAtlasBreadcrumbLayout.CrumbWidth(AIndex: Integer): Integer;
begin
  Canvas.Font := Font;
  if AIndex = High(FCrumbs) then
  begin
    Canvas.Font.Style := [fsBold];
  end;
  Result := Canvas.TextWidth(FCrumbs[AIndex].Text) + Scale(8);
  if FCrumbs[AIndex].Badge.Code <> '' then
  begin
    Inc(Result, BadgeWidth + Scale(4));
  end;
  Canvas.Font := Font;
end;

function TAtlasBreadcrumbLayout.GetFirstShown: Integer;
begin
  // Die Aufteilung entsteht erst beim Zeichnen; nach SetCrumbs oder Größenänderung hier nachholen.
  Layout;
  Result := FFirstShown;
end;

function TAtlasBreadcrumbLayout.TotalWidth(out AWidths: TArray<Integer>): Integer;
var
  Index: Integer;
begin
  SetLength(AWidths, Length(FCrumbs));
  Result := 0;
  for Index := 0 to High(FCrumbs) do
  begin
    AWidths[Index] := CrumbWidth(Index);
    Inc(Result, AWidths[Index]);
  end;
  Inc(Result, High(FCrumbs) * SeparatorWidth);
  if TrailingSeparator then
  begin
    Inc(Result, SeparatorWidth);
  end;
end;

procedure TAtlasBreadcrumbLayout.PlaceCrumbs(const AWidths: TArray<Integer>; ARight: Integer);
var
  Index, Left_: Integer;
begin
  Left_ := Scale(4);
  if FFirstShown > 0 then
  begin
    Inc(Left_, EllipsisWidth + SeparatorWidth);
  end;
  for Index := 0 to High(FCrumbs) do
  begin
    FRects[Index] := TRect.Empty;
    FSeparators[Index] := TRect.Empty;
    if Index < FFirstShown then
    begin
      Continue;
    end;
    FRects[Index] := Rect(Left_, 0, Min(Left_ + AWidths[Index], ARight), ClientHeight);
    Left_ := Left_ + AWidths[Index];
    if (Index < High(FCrumbs)) or TrailingSeparator then
    begin
      FSeparators[Index] := Rect(Left_, 0, Min(Left_ + SeparatorWidth, ARight), ClientHeight);
    end;
    Left_ := Left_ + SeparatorWidth;
  end;
end;

procedure TAtlasBreadcrumbLayout.Layout;
var
  Widths: TArray<Integer>;
  Total, Available, Right_: Integer;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  FLaidOut := True;
  SetLength(FRects, Length(FCrumbs));
  SetLength(FSeparators, Length(FCrumbs));
  FFirstShown := 0;
  if Length(FCrumbs) = 0 then
  begin
    Exit;
  end;
  Total := TotalWidth(Widths);
  Right_ := ContentRight;
  Available := Right_ - 2 * Scale(4);
  // Vorn Glieder weglassen, bis der Rest samt „…“ passt; das letzte bleibt.
  while (Total > Available) and (FFirstShown < High(FCrumbs)) do
  begin
    Dec(Total, Widths[FFirstShown] + SeparatorWidth);
    if FFirstShown = 0 then
    begin
      Inc(Total, EllipsisWidth + SeparatorWidth);
    end;
    Inc(FFirstShown);
  end;
  PlaceCrumbs(Widths, Right_);
  if FSelected < FFirstShown then
  begin
    FSelected := High(FCrumbs);
  end;
end;

function TAtlasBreadcrumbLayout.CrumbRect(AIndex: Integer): TRect;
begin
  Layout;
  if (AIndex < 0) or (AIndex > High(FRects)) then
  begin
    Exit(TRect.Empty);
  end;
  Result := FRects[AIndex];
end;

function TAtlasBreadcrumbLayout.TrailingSeparator: Boolean;
begin
  Result := (Length(FCrumbs) > 0) and (Length(FCrumbs[High(FCrumbs)].Children) > 0);
end;

function TAtlasBreadcrumbLayout.SeparatorRect(AIndex: Integer): TRect;
begin
  Layout;
  if (AIndex < 0) or (AIndex > High(FSeparators)) then
  begin
    Exit(TRect.Empty);
  end;
  Result := FSeparators[AIndex];
end;

function TAtlasBreadcrumbLayout.SeparatorAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  Layout;
  if (Y >= 0) and (Y < ClientHeight) then
  begin
    for Index := FFirstShown to High(FSeparators) do
    begin
      if not FSeparators[Index].IsEmpty and (X >= FSeparators[Index].Left) and (X < FSeparators[Index].Right) and
        (Length(FCrumbs[Index].Children) > 0) then
      begin
        Exit(Index);
      end;
    end;
  end;
  Result := -1;
end;

function TAtlasBreadcrumbLayout.CrumbAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  Layout;
  if (Y >= 0) and (Y < ClientHeight) then
  begin
    for Index := FFirstShown to High(FRects) do
    begin
      if not FRects[Index].IsEmpty and (X >= FRects[Index].Left) and (X < FRects[Index].Right) then
      begin
        Exit(Index);
      end;
    end;
  end;
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

function TAtlasBreadcrumbBar.DrawBadge(const ACrumb: TAtlasCrumb; ALeft: Integer): Integer;
var
  Box: TRect;
  BoxHeight, Radius: Integer;
begin
  Result := ALeft;
  if ACrumb.Badge.Code = '' then
  begin
    Exit;
  end;
  BoxHeight := Scale(15);
  Box := Rect(ALeft, (ClientHeight - BoxHeight) div 2, ALeft + BadgeWidth, (ClientHeight - BoxHeight) div 2 +
    BoxHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Badges[ACrumb.Badge.Kind].Background);
  Canvas.Pen.Color := Canvas.Brush.Color;
  Radius := Scale(4);
  Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, Radius, Radius);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -Round(Box.Height * 0.62);
  Canvas.Font.Color := ToColor(Colors.Badges[ACrumb.Badge.Kind].Text);
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(ACrumb.Badge.Code), -1, Box, DT_CENTER or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
  Result := Box.Right + Scale(4);
end;

procedure TAtlasBreadcrumbBar.DrawCrumb(AIndex: Integer);
var
  Crumb: TAtlasCrumb;
  Area, Part: TRect;
  Left_, Radius: Integer;
begin
  Crumb := FCrumbs[AIndex];
  Area := FRects[AIndex];
  Canvas.Brush.Style := bsSolid;
  if ((Hot = AIndex) and Clickable(AIndex)) or ((AIndex = FSelected) and Focused) then
  begin
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.Pen.Color := ToColor(Colors.Selection);
    if Focused and (AIndex = FSelected) then
    begin
      Canvas.Pen.Color := ToColor(Colors.Accent);
    end;
    Radius := Scale(4);
    Canvas.RoundRect(Area.Left, Area.Top + Scale(2), Area.Right, Area.Bottom - Scale(2), Radius, Radius);
  end;
  Left_ := DrawBadge(Crumb, Area.Left + Scale(4));
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  if AIndex = High(FCrumbs) then
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Text);
  end
  else
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
  end;
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
    begin
      DrawSeparator(Index);
    end;
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
  begin
    Exit(SeparatorPart + mIndex);
  end;
  Result := CrumbAt(X, Y);
  if Result < 0 then
  begin
    Result := PartNone;
  end;
end;

function TAtlasBreadcrumbBar.PartHint(APart: Integer): string;
begin
  // Hinweis je Teil: Glied (Menü, Strg+Klick) oder „›“ (Kinder).
  if APart >= SeparatorPart then
  begin
    Result := FSeparatorHint;
  end
  else if Clickable(APart) then
  begin
    Result := FCrumbHint;
  end
  else
  begin
    Result := '';
  end;
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
  begin
    Exit;
  end;
  FSelected := Index;
  Invalidate;
  // Ohne Geschwister gibt es kein Menü; dann springt auch der einfache Klick.
  if (ssCtrl in AShift) or (Length(FCrumbs[Index].Siblings) = 0) then
  begin
    Jump(Index, ssShift in AShift);
  end
  else
  begin
    OpenMenu(Index);
  end;
end;

procedure TAtlasBreadcrumbBar.OpenMenu(AIndex: Integer);
var
  Area: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or (Length(FCrumbs[AIndex].Siblings) = 0) or
    not Assigned(FOnOpenMenu) then
  begin
    Exit;
  end;
  Area := CrumbRect(AIndex);
  FOnOpenMenu(AIndex, ClientToScreen(Point(Area.Left, ClientHeight)));
end;

procedure TAtlasBreadcrumbBar.OpenChildren(AIndex: Integer);
var
  Area: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or (Length(FCrumbs[AIndex].Children) = 0) or
    not Assigned(FOnOpenChildren) then
  begin
    Exit;
  end;
  Area := SeparatorRect(AIndex);
  // Ohne „›“ (letztes Glied ohne Platz) unter dem Glied selbst.
  if Area.IsEmpty then
  begin
    Area := CrumbRect(AIndex);
  end;
  FOnOpenChildren(AIndex, ClientToScreen(Point(Area.Left, ClientHeight)));
end;

procedure TAtlasBreadcrumbBar.Jump(AIndex: Integer; ADeclaration: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or not Assigned(FOnJump) then
  begin
    Exit;
  end;
  if (FCrumbs[AIndex].Node < 0) and (FCrumbs[AIndex].Badge.Kind <> TAtlasBadgeKind.Unit_) then
  begin
    Exit;
  end;
  FOnJump(AIndex, ADeclaration);
end;

procedure TAtlasBreadcrumbBar.FocusLast;
begin
  FSelected := High(FCrumbs);
  if CanFocus then
  begin
    SetFocus;
  end;
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
        begin
          OpenChildren(FSelected);
        end
        else
        begin
          Jump(FSelected, ssShift in Shift);
        end;
      end
      else
      begin
        OpenMenu(FSelected);
      end;
    VK_ESCAPE:
      if Assigned(FOnLeave) then
      begin
        FOnLeave();
      end;
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
  begin
    Result := Result + ' ' + Control.Name;
  end;
end;

function TAtlasBreadcrumbLayout.WindowProblem: string;
begin
  Result := '';
  if not HandleAllocated then
  begin
    Result := 'Leiste hat kein Fenster';
  end
  else if GetWindowThreadProcessId(Handle, nil) <> MainThreadID then
  begin
    Result := 'Fenster gehört einem anderen Thread';
  end
  else if (Parent = nil) or not Parent.HandleAllocated or (GetParent(Handle) <> Parent.Handle) then
  begin
    Result := 'Fenster hängt an einem anderen Elternfenster';
  end
  else if not IsWindowEnabled(Handle) then
  begin
    Result := Format('Fenster ist gesperrt (Enabled %s)', [BoolToStr(Enabled, True)]);
  end
  else if GetWindowLongPtr(Handle, GWL_STYLE) and WS_VISIBLE = 0 then
  begin
    Result := 'Fenster ist ausgeblendet';
  end;
end;

/// <summary>Liegt der Bildschirmpunkt außerhalb des Fensters von AControl, außerhalb der Client-Fläche seines
/// Elternfensters oder außerhalb seiner Fensterregion? '' = nein.</summary>
function PlaceProblem(AControl: TWinControl; const AScreenPoint: TPoint): string;
var
  Bounds: TRect;
  Region: HRGN;
begin
  Result := '';
  GetWindowRect(AControl.Handle, Bounds);
  if not PtInRect(Bounds, AScreenPoint) then
  begin
    Exit(Format('Punkt (%d, %d) liegt außerhalb des Fensters (%d, %d, %d, %d)', [AScreenPoint.X,
      AScreenPoint.Y, Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom]));
  end;
  // Kinder trifft Windows nur in der Client-Fläche des Elternfensters; im Rahmen bekommt es das Elternfenster.
  if not PtInRect(AControl.Parent.ClientRect, AControl.Parent.ScreenToClient(AScreenPoint)) then
  begin
    Exit('Punkt liegt im Rahmen des Elternfensters, nicht in seiner Client-Fläche');
  end;
  Region := CreateRectRgn(0, 0, 0, 0);
  try
    // Die Region ist relativ zur linken oberen Ecke des Fensters; ERROR = keine Region gesetzt.
    if (GetWindowRgn(AControl.Handle, Region) <> ERROR) and
      not PtInRegion(Region, AScreenPoint.X - Bounds.Left, AScreenPoint.Y - Bounds.Top) then
    begin
      Result := 'Punkt liegt außerhalb der Fensterregion (SetWindowRgn)';
    end;
  finally
    DeleteObject(Region);
  end;
end;

/// <summary>Lässt das Fenster von AControl die Maus durch (Stil, WM_NCHITTEST)? '' = nein.</summary>
function PassThroughProblem(AControl: TWinControl; const AScreenPoint: TPoint): string;
var
  ExStyle: NativeInt;
  HitTest: LRESULT;
begin
  Result := '';
  ExStyle := GetWindowLongPtr(AControl.Handle, GWL_EXSTYLE);
  if ExStyle and WS_EX_TRANSPARENT <> 0 then
  begin
    Exit('Fenster hat WS_EX_TRANSPARENT');
  end;
  if ExStyle and WS_EX_LAYERED <> 0 then
  begin
    Exit('Fenster ist geschichtet (WS_EX_LAYERED)');
  end;
  // Über die ganze Fensterprozedur, also auch über Unterklassen und Stil-Hooks der IDE.
  HitTest := SendMessage(AControl.Handle, WM_NCHITTEST, 0, MakeLParam(Word(AScreenPoint.X), Word(AScreenPoint.Y)));
  if Integer(HitTest) = HTTRANSPARENT then
  begin
    Result := 'WM_NCHITTEST liefert HTTRANSPARENT';
  end;
end;

/// <summary>Liegt ein Geschwisterfenster über AControl? '' = nein.</summary>
function CoverProblem(AControl: TWinControl; const AScreenPoint: TPoint): string;
var
  Topmost: HWND;
begin
  Result := '';
  Topmost := ChildWindowFromPointEx(AControl.Parent.Handle, AControl.Parent.ScreenToClient(AScreenPoint),
    CWP_SKIPINVISIBLE);
  if (Topmost <> 0) and (Topmost <> AControl.Handle) and (Topmost <> AControl.Parent.Handle) then
  begin
    Result := Format('Geschwisterfenster liegt darüber (%s)', [WindowLabel(Topmost)]);
  end;
end;

function TAtlasBreadcrumbLayout.HitProblem(const AScreenPoint: TPoint): string;
begin
  Result := WindowProblem;
  if Result = '' then
  begin
    Result := PlaceProblem(Self, AScreenPoint);
  end;
  if Result = '' then
  begin
    Result := PassThroughProblem(Self, AScreenPoint);
  end;
  if Result = '' then
  begin
    Result := CoverProblem(Self, AScreenPoint);
  end;
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
