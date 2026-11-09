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
// - Passt der Pfad nicht, fallen zuerst Glieder mit hohem Rang (Drop) weg,
//   vorn beginnend, erst dann vorn die übrigen.
// - Ein Glied mit Sichtbarkeitsmarke (#1765) zeigt sie vor dem Namen; der
//   Hinweis nennt Sichtbarkeit und Zeile der Deklaration (MarkHint).
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
    /// <summary>Glied fällt wegen seines Rangs (Drop) weg.</summary>
    FDropped: TArray<Boolean>;
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
    /// <summary>Glieder nach Rang weglassen, bis AWidth passt; liefert die Breite danach.</summary>
    function DropByRank(const AWidths: TArray<Integer>; AWidth, AAvailable: Integer): Integer;
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
    function CrumbAt(AX, AY: Integer): Integer;
    /// <summary>Fläche des Glieds (Client); leer, wenn es wegen der Breite entfällt.</summary>
    function CrumbRect(AIndex: Integer): TRect;
    /// <summary>„›“ hinter dem Glied unter dem Punkt (Client), nur wenn das Glied Kinder hat; -1 = keins.</summary>
    function SeparatorAt(AX, AY: Integer): Integer;
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
    /// <summary>Wird das Glied gezeigt (nicht vorn gekürzt und nicht nach Rang weggelassen)?</summary>
    function Shown(AIndex: Integer): Boolean;
    property EmptyText: string read FEmptyText write SetEmptyText;
  end;

  TAtlasBreadcrumbBar = class(TAtlasBreadcrumbLayout)
  private const
    /// <summary>Teil des „›“ hinter Glied i: SeparatorPart + i.</summary>
    cSeparatorPart = $10000;
  private
    FCrumbHint: string;
    FSeparatorHint: string;
    FMarkHint: string;
    FOnOpenMenu: TAtlasCrumbMenuEvent;
    FOnOpenChildren: TAtlasCrumbMenuEvent;
    FOnJump: TAtlasCrumbJumpEvent;
    FOnLeave: TProc;
    procedure DrawCrumb(AIndex: Integer);
    /// <summary>Auswahl zum nächsten gezeigten Glied in Richtung AStep (-1, 1).</summary>
    procedure MoveSelection(AStep: Integer);
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
    /// <summary>Hinweis zur Sichtbarkeitsmarke (#1765), Format mit Sichtbarkeit (%s) und Zeile (%d).</summary>
    property MarkHint: string read FMarkHint write FMarkHint;
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
  cSeparator = '›';
  cEllipsis = '…';

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Gleiche Sprungziele (Sichtbarkeitsabschnitte, #1759, mit Marke und Mitgliederzahl, #1768)?</summary>
function SamePlaces(const A, B: TArray<TAtlasCrumbPlace>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := (A[mIndex].Text = B[mIndex].Text) and (A[mIndex].Line = B[mIndex].Line) and
      (A[mIndex].Character = B[mIndex].Character) and (A[mIndex].Group = B[mIndex].Group) and
      (A[mIndex].Depth = B[mIndex].Depth) and (A[mIndex].Mark = B[mIndex].Mark) and
      (A[mIndex].Count = B[mIndex].Count);
    Inc(mIndex);
  end;
end;

/// <summary>Angezeigter Text des Glieds: Sichtbarkeitsmarke (#1765) und Name.</summary>
function CrumbCaption(const ACrumb: TAtlasCrumb): string;
begin
  Result := ACrumb.Text;
  if ACrumb.Mark <> '' then
  begin
    Result := ACrumb.Mark + ' ' + Result;
  end;
end;

function SameCrumbs(const A, B: TAtlasCrumbs): Boolean;
var
  mIndex, mSibling: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := (A[mIndex].Text = B[mIndex].Text) and (A[mIndex].Node = B[mIndex].Node) and
      (A[mIndex].Badge.Kind = B[mIndex].Badge.Kind) and (A[mIndex].Badge.Code = B[mIndex].Badge.Code) and
      (A[mIndex].Current = B[mIndex].Current) and (Length(A[mIndex].Siblings) = Length(B[mIndex].Siblings)) and
      (Length(A[mIndex].Children) = Length(B[mIndex].Children)) and (A[mIndex].Implicit = B[mIndex].Implicit) and
      SamePlaces(A[mIndex].Places, B[mIndex].Places) and (A[mIndex].Mark = B[mIndex].Mark) and
      (A[mIndex].MarkVisibility = B[mIndex].MarkVisibility) and (A[mIndex].MarkLine = B[mIndex].MarkLine) and
      (A[mIndex].Drop = B[mIndex].Drop) and (A[mIndex].SectionType = B[mIndex].SectionType);
    mSibling := 0;
    while Result and (mSibling <= High(A[mIndex].Siblings)) do
    begin
      Result := A[mIndex].Siblings[mSibling] = B[mIndex].Siblings[mSibling];
      Inc(mSibling);
    end;
    mSibling := 0;
    while Result and (mSibling <= High(A[mIndex].Children)) do
    begin
      Result := A[mIndex].Children[mSibling] = B[mIndex].Children[mSibling];
      Inc(mSibling);
    end;
    Inc(mIndex);
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
  SetHot(cPartNone);
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
  mIndex: Integer;
  mChild: TControl;
begin
  Result := ClientWidth;
  for mIndex := 0 to ControlCount - 1 do
  begin
    mChild := Controls[mIndex];
    if mChild.Visible and (mChild.Align = alRight) then
    begin
      Result := Min(Result, mChild.Left);
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
  Result := Canvas.TextWidth(cSeparator) + Scale(10);
end;

function TAtlasBreadcrumbLayout.EllipsisWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextWidth(cEllipsis) + Scale(6);
end;

function TAtlasBreadcrumbLayout.CrumbWidth(AIndex: Integer): Integer;
begin
  Canvas.Font := Font;
  if AIndex = High(FCrumbs) then
  begin
    Canvas.Font.Style := [fsBold];
  end;
  Result := Canvas.TextWidth(CrumbCaption(FCrumbs[AIndex])) + Scale(8);
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
  mIndex: Integer;
begin
  SetLength(AWidths, Length(FCrumbs));
  Result := 0;
  for mIndex := 0 to High(FCrumbs) do
  begin
    AWidths[mIndex] := CrumbWidth(mIndex);
    Inc(Result, AWidths[mIndex]);
  end;
  Inc(Result, High(FCrumbs) * SeparatorWidth);
  if TrailingSeparator then
  begin
    Inc(Result, SeparatorWidth);
  end;
end;

procedure TAtlasBreadcrumbLayout.PlaceCrumbs(const AWidths: TArray<Integer>; ARight: Integer);
var
  mIndex, mLeft_: Integer;
begin
  mLeft_ := Scale(4);
  if FFirstShown > 0 then
  begin
    Inc(mLeft_, EllipsisWidth + SeparatorWidth);
  end;
  for mIndex := 0 to High(FCrumbs) do
  begin
    FRects[mIndex] := TRect.Empty;
    FSeparators[mIndex] := TRect.Empty;
    if not Shown(mIndex) then
    begin
      Continue;
    end;
    FRects[mIndex] := Rect(mLeft_, 0, Min(mLeft_ + AWidths[mIndex], ARight), ClientHeight);
    mLeft_ := mLeft_ + AWidths[mIndex];
    if (mIndex < High(FCrumbs)) or TrailingSeparator then
    begin
      FSeparators[mIndex] := Rect(mLeft_, 0, Min(mLeft_ + SeparatorWidth, ARight), ClientHeight);
    end;
    mLeft_ := mLeft_ + SeparatorWidth;
  end;
end;

procedure TAtlasBreadcrumbLayout.Layout;
var
  mWidths: TArray<Integer>;
  mTotal, mAvailable, mRight_: Integer;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  FLaidOut := True;
  SetLength(FRects, Length(FCrumbs));
  SetLength(FSeparators, Length(FCrumbs));
  FDropped := nil;
  SetLength(FDropped, Length(FCrumbs));
  FFirstShown := 0;
  if Length(FCrumbs) = 0 then
  begin
    Exit;
  end;
  mTotal := TotalWidth(mWidths);
  mRight_ := ContentRight;
  mAvailable := mRight_ - 2 * Scale(4);
  mTotal := DropByRank(mWidths, mTotal, mAvailable);
  // Vorn Glieder weglassen, bis der Rest samt „…“ passt; das letzte bleibt.
  while (mTotal > mAvailable) and (FFirstShown < High(FCrumbs)) do
  begin
    if not FDropped[FFirstShown] then
    begin
      Dec(mTotal, mWidths[FFirstShown] + SeparatorWidth);
    end;
    if FFirstShown = 0 then
    begin
      Inc(mTotal, EllipsisWidth + SeparatorWidth);
    end;
    Inc(FFirstShown);
  end;
  PlaceCrumbs(mWidths, mRight_);
  if not Shown(FSelected) then
  begin
    FSelected := High(FCrumbs);
  end;
end;

function TAtlasBreadcrumbLayout.DropByRank(const AWidths: TArray<Integer>; AWidth, AAvailable: Integer): Integer;
var
  mRank, mIndex: Integer;
begin
  Result := AWidth;
  for mRank := 2 downto 1 do
  begin
    // Das letzte Glied bleibt immer.
    for mIndex := 0 to High(FCrumbs) - 1 do
    begin
      if Result <= AAvailable then
      begin
        Exit;
      end;
      if FCrumbs[mIndex].Drop = mRank then
      begin
        FDropped[mIndex] := True;
        Dec(Result, AWidths[mIndex] + SeparatorWidth);
      end;
    end;
  end;
end;

function TAtlasBreadcrumbLayout.Shown(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= FFirstShown) and (AIndex <= High(FCrumbs)) and
    ((AIndex > High(FDropped)) or not FDropped[AIndex]);
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

function TAtlasBreadcrumbLayout.SeparatorAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  Layout;
  if (AY >= 0) and (AY < ClientHeight) then
  begin
    for mIndex := FFirstShown to High(FSeparators) do
    begin
      if not FSeparators[mIndex].IsEmpty and (AX >= FSeparators[mIndex].Left) and (AX < FSeparators[mIndex].Right) and
        (Length(FCrumbs[mIndex].Children) > 0) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

function TAtlasBreadcrumbLayout.CrumbAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  Layout;
  if (AY >= 0) and (AY < ClientHeight) then
  begin
    for mIndex := FFirstShown to High(FRects) do
    begin
      if not FRects[mIndex].IsEmpty and (AX >= FRects[mIndex].Left) and (AX < FRects[mIndex].Right) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

procedure TAtlasBreadcrumbBar.DrawSeparator(ALeft: Integer; const AText: string);
var
  mPart: TRect;
begin
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  mPart := Rect(ALeft, 0, ALeft + Canvas.TextWidth(AText) + Scale(10), ClientHeight);
  DrawText(Canvas.Handle, PChar(AText), -1, mPart, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TAtlasBreadcrumbBar.DrawSeparator(AIndex: Integer);
var
  mArea: TRect;
  mRadius: Integer;
begin
  mArea := FSeparators[AIndex];
  if Hot = cSeparatorPart + AIndex then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.Pen.Color := ToColor(Colors.Selection);
    mRadius := Scale(4);
    Canvas.RoundRect(mArea.Left + Scale(1), mArea.Top + Scale(2), mArea.Right - Scale(1), mArea.Bottom - Scale(2),
      mRadius,
      mRadius);
  end;
  DrawSeparator(mArea.Left, cSeparator);
end;

function TAtlasBreadcrumbBar.DrawBadge(const ACrumb: TAtlasCrumb; ALeft: Integer): Integer;
var
  mBox: TRect;
  mBoxHeight, mRadius: Integer;
begin
  Result := ALeft;
  if ACrumb.Badge.Code = '' then
  begin
    Exit;
  end;
  mBoxHeight := Scale(15);
  mBox := Rect(ALeft, (ClientHeight - mBoxHeight) div 2, ALeft + BadgeWidth, (ClientHeight - mBoxHeight) div 2 +
    mBoxHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Badges[ACrumb.Badge.Kind].Background);
  Canvas.Pen.Color := Canvas.Brush.Color;
  mRadius := Scale(4);
  Canvas.RoundRect(mBox.Left, mBox.Top, mBox.Right, mBox.Bottom, mRadius, mRadius);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -Round(mBox.Height * 0.62);
  Canvas.Font.Color := ToColor(Colors.Badges[ACrumb.Badge.Kind].Text);
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(ACrumb.Badge.Code), -1, mBox, DT_CENTER or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
  Result := mBox.Right + Scale(4);
end;

procedure TAtlasBreadcrumbBar.DrawCrumb(AIndex: Integer);
var
  mCrumb: TAtlasCrumb;
  mArea, mPart: TRect;
  mLeft_, mRadius: Integer;
begin
  mCrumb := FCrumbs[AIndex];
  mArea := FRects[AIndex];
  Canvas.Brush.Style := bsSolid;
  if ((Hot = AIndex) and Clickable(AIndex)) or ((AIndex = FSelected) and Focused) then
  begin
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.Pen.Color := ToColor(Colors.Selection);
    if Focused and (AIndex = FSelected) then
    begin
      Canvas.Pen.Color := ToColor(Colors.Accent);
    end;
    mRadius := Scale(4);
    Canvas.RoundRect(mArea.Left, mArea.Top + Scale(2), mArea.Right, mArea.Bottom - Scale(2), mRadius, mRadius);
  end;
  mLeft_ := DrawBadge(mCrumb, mArea.Left + Scale(4));
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
  // Implizite Sichtbarkeit (#1759) steht nicht im Quelltext: kursiv.
  if mCrumb.Implicit then
  begin
    Canvas.Font.Style := Canvas.Font.Style + [fsItalic];
  end;
  mPart := Rect(mLeft_, 0, mArea.Right - Scale(2), ClientHeight);
  DrawText(Canvas.Handle, PChar(CrumbCaption(mCrumb)), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Font := Font;
end;

procedure TAtlasBreadcrumbBar.Paint;
var
  mIndex: Integer;
  mPart: TRect;
begin
  Layout;
  PaintChrome(False);
  if Length(FCrumbs) = 0 then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
    mPart := Rect(Scale(8), 0, ContentRight - Scale(4), ClientHeight);
    DrawText(Canvas.Handle, PChar(FEmptyText), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Exit;
  end;
  if FFirstShown > 0 then
  begin
    DrawSeparator(Scale(2), cEllipsis);
    DrawSeparator(Scale(4) + EllipsisWidth, cSeparator);
  end;
  for mIndex := FFirstShown to High(FCrumbs) do
  begin
    if not Shown(mIndex) then
    begin
      Continue;
    end;
    DrawCrumb(mIndex);
    if not FSeparators[mIndex].IsEmpty then
    begin
      DrawSeparator(mIndex);
    end;
  end;
end;

function TAtlasBreadcrumbBar.Clickable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FCrumbs)) and
    (TAtlasBreadcrumbs.HasMenu(FCrumbs[AIndex]) or (FCrumbs[AIndex].Node >= 0));
end;

function TAtlasBreadcrumbBar.PartAt(X, Y: Integer): Integer;
var
  mIndex: Integer;
begin
  mIndex := SeparatorAt(X, Y);
  if mIndex >= 0 then
  begin
    Exit(cSeparatorPart + mIndex);
  end;
  Result := CrumbAt(X, Y);
  if Result < 0 then
  begin
    Result := cPartNone;
  end;
end;

function TAtlasBreadcrumbBar.PartHint(APart: Integer): string;
var
  mMark: string;
begin
  // Hinweis je Teil: Glied (Menü, Strg+Klick) oder „›“ (Kinder).
  if APart >= cSeparatorPart then
  begin
    Exit(FSeparatorHint);
  end;
  Result := '';
  if Clickable(APart) then
  begin
    Result := FCrumbHint;
  end;
  // Sichtbarkeitsmarke (#1765): Sichtbarkeit und Zeile der Deklaration (1-basiert) zuerst.
  if (APart < 0) or (APart > High(FCrumbs)) or (FCrumbs[APart].Mark = '') or (FMarkHint = '') then
  begin
    Exit;
  end;
  mMark := Format(FMarkHint, [FCrumbs[APart].MarkVisibility, FCrumbs[APart].MarkLine + 1]);
  if Result = '' then
  begin
    Result := mMark;
  end
  else
  begin
    Result := mMark + sLineBreak + Result;
  end;
end;

function TAtlasBreadcrumbBar.PartEnabled(APart: Integer): Boolean;
begin
  Result := (APart >= cSeparatorPart) or Clickable(APart);
end;

procedure TAtlasBreadcrumbBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  // Erst beim Loslassen (Vorfahr): Beim Drücken holt die IDE den Fokus zurück in den Editor, das Menü ginge sofort
  // wieder zu.
  if APart >= cSeparatorPart then
  begin
    OpenChildren(APart - cSeparatorPart);
    Exit;
  end;
  mIndex := APart;
  if mIndex < 0 then
  begin
    Exit;
  end;
  FSelected := mIndex;
  Invalidate;
  // Ohne Geschwister gibt es kein Menü; dann springt auch der einfache Klick.
  if (ssCtrl in AShift) or not TAtlasBreadcrumbs.HasMenu(FCrumbs[mIndex]) then
  begin
    Jump(mIndex, ssShift in AShift);
  end
  else
  begin
    OpenMenu(mIndex);
  end;
end;

procedure TAtlasBreadcrumbBar.OpenMenu(AIndex: Integer);
var
  mArea: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or not TAtlasBreadcrumbs.HasMenu(FCrumbs[AIndex]) or
    not Assigned(FOnOpenMenu) then
  begin
    Exit;
  end;
  mArea := CrumbRect(AIndex);
  FOnOpenMenu(AIndex, ClientToScreen(Point(mArea.Left, ClientHeight)));
end;

procedure TAtlasBreadcrumbBar.OpenChildren(AIndex: Integer);
var
  mArea: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or (Length(FCrumbs[AIndex].Children) = 0) or
    not Assigned(FOnOpenChildren) then
  begin
    Exit;
  end;
  mArea := SeparatorRect(AIndex);
  // Ohne „›“ (letztes Glied ohne Platz) unter dem Glied selbst.
  if mArea.IsEmpty then
  begin
    mArea := CrumbRect(AIndex);
  end;
  FOnOpenChildren(AIndex, ClientToScreen(Point(mArea.Left, ClientHeight)));
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

procedure TAtlasBreadcrumbBar.MoveSelection(AStep: Integer);
var
  mIndex: Integer;
begin
  mIndex := FSelected + AStep;
  while (mIndex >= 0) and (mIndex <= High(FCrumbs)) and not Shown(mIndex) do
  begin
    Inc(mIndex, AStep);
  end;
  if (mIndex >= 0) and (mIndex <= High(FCrumbs)) then
  begin
    FSelected := mIndex;
    Invalidate;
  end;
end;

procedure TAtlasBreadcrumbBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_LEFT:
      MoveSelection(-1);
    VK_RIGHT:
      MoveSelection(1);
    VK_HOME:
      begin
        FSelected := -1;
        MoveSelection(1);
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
  mWindowClass: array[0..255] of Char;
  mControl: TWinControl;
begin
  mWindowClass[0] := #0;
  GetClassName(AWindow, mWindowClass, Length(mWindowClass));
  Result := string(mWindowClass);
  mControl := FindControl(AWindow);
  if mControl <> nil then
  begin
    Result := Result + ' ' + mControl.Name;
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
  mBounds: TRect;
  mRegion: HRGN;
begin
  Result := '';
  GetWindowRect(AControl.Handle, mBounds);
  if not PtInRect(mBounds, AScreenPoint) then
  begin
    Exit(Format('Punkt (%d, %d) liegt außerhalb des Fensters (%d, %d, %d, %d)', [AScreenPoint.X,
      AScreenPoint.Y, mBounds.Left, mBounds.Top, mBounds.Right, mBounds.Bottom]));
  end;
  // Kinder trifft Windows nur in der Client-Fläche des Elternfensters; im Rahmen bekommt es das Elternfenster.
  if not PtInRect(AControl.Parent.ClientRect, AControl.Parent.ScreenToClient(AScreenPoint)) then
  begin
    Exit('Punkt liegt im Rahmen des Elternfensters, nicht in seiner Client-Fläche');
  end;
  mRegion := CreateRectRgn(0, 0, 0, 0);
  try
    // Die Region ist relativ zur linken oberen Ecke des Fensters; ERROR = keine Region gesetzt.
    if (GetWindowRgn(AControl.Handle, mRegion) <> ERROR) and
      not PtInRegion(mRegion, AScreenPoint.X - mBounds.Left, AScreenPoint.Y - mBounds.Top) then
    begin
      Result := 'Punkt liegt außerhalb der Fensterregion (SetWindowRgn)';
    end;
  finally
    DeleteObject(mRegion);
  end;
end;

/// <summary>Lässt das Fenster von AControl die Maus durch (Stil, WM_NCHITTEST)? '' = nein.</summary>
function PassThroughProblem(AControl: TWinControl; const AScreenPoint: TPoint): string;
var
  mExStyle: NativeInt;
  mHitTest: LRESULT;
begin
  Result := '';
  mExStyle := GetWindowLongPtr(AControl.Handle, GWL_EXSTYLE);
  if mExStyle and WS_EX_TRANSPARENT <> 0 then
  begin
    Exit('Fenster hat WS_EX_TRANSPARENT');
  end;
  if mExStyle and WS_EX_LAYERED <> 0 then
  begin
    Exit('Fenster ist geschichtet (WS_EX_LAYERED)');
  end;
  // Über die ganze Fensterprozedur, also auch über Unterklassen und Stil-Hooks der IDE.
  mHitTest := SendMessage(AControl.Handle, WM_NCHITTEST, 0, MakeLParam(Word(AScreenPoint.X), Word(AScreenPoint.Y)));
  if Integer(mHitTest) = HTTRANSPARENT then
  begin
    Result := 'WM_NCHITTEST liefert HTTRANSPARENT';
  end;
end;

/// <summary>Liegt ein Geschwisterfenster über AControl? '' = nein.</summary>
function CoverProblem(AControl: TWinControl; const AScreenPoint: TPoint): string;
var
  mTopmost: HWND;
begin
  Result := '';
  mTopmost := ChildWindowFromPointEx(AControl.Parent.Handle, AControl.Parent.ScreenToClient(AScreenPoint),
    CWP_SKIPINVISIBLE);
  if (mTopmost <> 0) and (mTopmost <> AControl.Handle) and (mTopmost <> AControl.Parent.Handle) then
  begin
    Result := Format('Geschwisterfenster liegt darüber (%s)', [WindowLabel(mTopmost)]);
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
