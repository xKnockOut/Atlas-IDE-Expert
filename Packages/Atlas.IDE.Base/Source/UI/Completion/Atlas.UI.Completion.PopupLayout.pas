unit Atlas.UI.Completion.PopupLayout;

// Vervollständigungs-Popup (#410), Stufe Lage: wo Liste, Zeilen, Chips, Warnleiste und Detailpanel liegen, wie
// breit die Liste wird (#416) und wohin das Fenster kommt (darunter, sonst darüber; nie über den Monitorrand).
// Dazu die Schnittstelle des Detailpanels (#424, #425, #428, #654). Kette und Aussehen: Atlas.UI.Completion.Popup.

interface

uses
  System.Types,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation,
  Atlas.UI.Completion.PopupTexts,
  Atlas.UI.Completion.PopupState;

type
  TAtlasCompletionPopupLayout = class(TAtlasCompletionPopupState)
  protected
    function Collapsed: Boolean;
    function Logical(APixels: Integer): Integer;
    function ListWidth: Integer;
    function PanelWidth: Integer;
    function ChipsHeight: Integer;
    /// <summary>Höhe der Warnleiste (#457); 0 ohne Hinweis.</summary>
    function SyntaxHeight: Integer;
    function ListTop: Integer;
    /// <summary>Linker Rand der Listenspalte im Fenster.</summary>
    function ListLeft: Integer;
    function ListRight: Integer;
    function ListHeight: Integer;
    function PanelHeight: Integer;
    function PanelRect: TRect;
    /// <summary>Höchste Höhe des Panels: größerer Platz unter bzw. über dem Wort, mindestens die Liste.</summary>
    function PanelCap: Integer;
    function DocActive: Boolean;
    procedure Relayout;
    function RowAt(AX, AY: Integer): Integer;
    function RowRect(ARow: Integer): TRect;
    procedure EnsureSelectedVisible;
    procedure PlaceAt(AListWidth, AHeight: Integer);
    function HitArea(AX, AY: Integer): TAtlasHitArea;
    /// <summary>Position (Anzeigereihenfolge) des Sterns unter (AX, AY); -1 ohne.</summary>
    function StarAt(AX, AY: Integer): Integer;
    function MeasureWidth: Integer;
    function TagWidth(const ATag: TAtlasTag): Integer;
    /// <summary>Tags der Zeile; ohne ShowVariantBranch fehlt „Zweig 0“ (#846).</summary>
    function ItemTags(const AItem: TAtlasCompletionItem): TAtlasTags;
    procedure PlaceAndShow;
    procedure WidthsChanged;
    /// <summary>Gezeigte Liste für die Texte der Fußzeile.</summary>
    function ListState: TAtlasCompletionList;
  public
    /// <summary>Details zum gewählten Eintrag im Panelbereich zeigen; öffnet ihn bei Bedarf.</summary>
    procedure ShowDetails(const ADetails: TAtlasItemDetails);
    /// <summary>Details leeren; ein offener Panelbereich bleibt mit Hinweis stehen.</summary>
    procedure ClearDetails;
    /// <summary>Panel ein- bzw. ausklappen (Strg+Q, #428).</summary>
    procedure TogglePanel;
    /// <summary>Gezeigte Überladung im Panel (#425); ACount 1 = keine Kopfzeile.</summary>
    procedure SetOverload(AIndex, ACount: Integer);
    /// <summary>Im Panel markierter Doku-Text (#654); '' ohne Markierung.</summary>
    function SelectedDocText: string;
    function PageSize: Integer;
    /// <summary>Caret-Rechteck in Bildschirmkoordinaten; vor dem ersten ShowList setzen.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    property VisibleRows: Integer read FVisibleRows write FVisibleRows;
    /// <summary>Geerbte Member abgeschwächt zeichnen (#419).</summary>
    property DimInherited: Boolean read FOptions.DimInherited write FOptions.DimInherited;
    /// <summary>Marke „Zweig 0“ an Feldern varianter Records (#846, completion.variantBranch); Vorgabe an.
    /// </summary>
    property ShowVariantBranch: Boolean read FOptions.ShowVariantBranch write FOptions.ShowVariantBranch;
    /// <summary>Der Server indiziert noch (#492, #457): Die Fußzeile meldet „eingeschränkt“; die Liste
    /// zeigt den vorhandenen Stand.</summary>
    property Limited: Boolean read FOptions.Limited write FOptions.Limited;
    /// <summary>Aktives Ziel („Win32 · Debug“) für die Fußzeile (#476); '' = keins bekannt.</summary>
    property Target: string read FOptions.Target write FOptions.Target;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.Core.Completion.Width,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Sets,
  Atlas.Core.Completion.Favorites,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Strings,
  Atlas.UI.Completion.Details;

{ TAtlasCompletionPopupLayout }

function TAtlasCompletionPopupLayout.Collapsed: Boolean;
begin
  Result := FPanel.Collapsed or FPanel.AutoCollapsed;
end;

function TAtlasCompletionPopupLayout.PanelWidth: Integer;
begin
  if not FPanel.Shown then
  begin
    Result := 0;
  end
  else if Collapsed then
  begin
    Result := Scale(cCollapsedPanelWidth);
  end
  else
  begin
    Result := Scale(FPanel.Width);
  end;
end;

function TAtlasCompletionPopupLayout.ListWidth: Integer;
begin
  Result := TAtlasPopupWidth.Effective(Scale(FManualListWidth), FSessionWidth);
end;

function TAtlasCompletionPopupLayout.Logical(APixels: Integer): Integer;
begin
  Result := MulDiv(APixels, 96, PPI);
end;

function TAtlasCompletionPopupLayout.ListLeft: Integer;
begin
  if FPanel.Shown and FPanel.Left then
  begin
    Result := PanelWidth;
  end
  else
  begin
    Result := 0;
  end;
end;

function TAtlasCompletionPopupLayout.ListRight: Integer;
begin
  Result := ListLeft + ListWidth;
end;

function TAtlasCompletionPopupLayout.ListHeight: Integer;
begin
  if FEmpty.Showing then
  begin
    Result := 2 * Pad + ChipsHeight + SyntaxHeight + 2 * RowHeight + FooterHeight;
  end
  else
  begin
    Result := 2 * Pad + ChipsHeight + SyntaxHeight + RowCount * RowHeight + FooterHeight;
  end;
end;

function TAtlasCompletionPopupLayout.PanelHeight: Integer;
begin
  if not FPanel.Shown or Collapsed then
  begin
    Exit(0);
  end;
  FDetailView.MaxHeight := PanelCap;
  Result := FDetailView.Render(TAtlasDetailSurface.Create(Canvas, Colors, Font, UIFont, PPI),
    Rect(0, 0, PanelWidth, 0), False);
  Canvas.Font := Font;
end;

function TAtlasCompletionPopupLayout.PanelRect: TRect;
begin
  if FPanel.Left then
  begin
    Result := Rect(0, 0, PanelWidth, ClientHeight);
  end
  else
  begin
    Result := Rect(ListRight, 0, ListRight + PanelWidth, ClientHeight);
  end;
end;

function TAtlasCompletionPopupLayout.PanelCap: Integer;
var
  mArea: TRect;
begin
  mArea := WorkAreaAt(FAnchor.TopLeft);
  Result := Max(ListHeight, Max(mArea.Bottom - FAnchor.Bottom, FAnchor.Top - mArea.Top) - Scale(8));
end;

function TAtlasCompletionPopupLayout.DocActive: Boolean;
begin
  Result := FPanel.Shown and not Collapsed and not FDetailView.Doc.IsEmpty;
end;

function TAtlasCompletionPopupLayout.SelectedDocText: string;
begin
  Result := FDetailView.Doc.SelectedText;
end;

procedure TAtlasCompletionPopupLayout.Relayout;
begin
  // Mit Panel wächst die Höhe nur, damit das Fenster beim Blättern nicht springt.
  if FPanel.Shown then
  begin
    FSessionHeight := Max(FSessionHeight, Max(ListHeight, PanelHeight));
  end
  else
  begin
    FSessionHeight := ListHeight;
  end;
  PlaceAt(ListWidth, FSessionHeight);
end;

procedure TAtlasCompletionPopupLayout.ShowDetails(const ADetails: TAtlasItemDetails);
begin
  FDetailView.Details := ADetails;
  if not FPanel.Shown and ADetails.IsEmpty then
  begin
    Exit;
  end;
  FPanel.Shown := True;
  if IsShown then
  begin
    Relayout;
  end;
  Invalidate;
end;

function TAtlasCompletionPopupLayout.ChipsHeight: Integer;
begin
  if not FChips.Visible or FEmpty.Showing then
  begin
    Exit(0);
  end;
  EnsureMetrics;
  Result := FMetrics.ChipsHeight;
end;

function TAtlasCompletionPopupLayout.SyntaxHeight: Integer;
begin
  if FSyntax.Trust = TAtlasSyntaxTrust.Sure then
  begin
    Exit(0);
  end;
  EnsureMetrics;
  Result := FMetrics.ChipsHeight;
end;

function TAtlasCompletionPopupLayout.ListTop: Integer;
begin
  Result := Pad + ChipsHeight + SyntaxHeight;
end;

procedure TAtlasCompletionPopupLayout.SetOverload(AIndex, ACount: Integer);
begin
  if (FDetailView.OverloadIndex = AIndex) and (FDetailView.OverloadCount = ACount) then
  begin
    Exit;
  end;
  FDetailView.OverloadIndex := AIndex;
  FDetailView.OverloadCount := ACount;
  if IsShown and FPanel.Shown then
  begin
    Relayout;
  end;
  Invalidate;
end;

procedure TAtlasCompletionPopupLayout.TogglePanel;
begin
  FPanel.Collapsed := not FPanel.Collapsed;
  if Assigned(FEvents.OnPanelToggled) then
  begin
    FEvents.OnPanelToggled(FPanel.Collapsed);
  end;
  if IsShown then
  begin
    Relayout;
  end;
  Invalidate;
end;

procedure TAtlasCompletionPopupLayout.ClearDetails;
begin
  FDetailView.Details := Default(TAtlasItemDetails);
  if FPanel.Shown then
  begin
    Invalidate;
  end;
end;

function TAtlasCompletionPopupLayout.PageSize: Integer;
begin
  Result := FVisibleRows;
end;

function TAtlasCompletionPopupLayout.RowRect(ARow: Integer): TRect;
var
  mHeight: Integer;
begin
  mHeight := RowHeight;
  Result := Rect(ListLeft + Pad, ListTop + ARow * mHeight, ListRight - Pad - ScrollReserve, ListTop + (ARow + 1) *
    mHeight);
end;

function TAtlasCompletionPopupLayout.RowAt(AX, AY: Integer): Integer;
begin
  if (AY < ListTop) or (AX < ListLeft) or (AX >= ListRight) then
  begin
    Exit(-1);
  end;
  Result := FTop + (AY - ListTop) div RowHeight;
  if (Result < FTop) or (Result >= Min(FTop + RowCount, Length(FOrder))) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasCompletionPopupLayout.EnsureSelectedVisible;
begin
  if FSelected < 0 then
  begin
    Exit;
  end;
  if FSelected < FTop then
  begin
    FTop := FSelected;
  end
  else if FSelected >= FTop + FVisibleRows then
  begin
    FTop := FSelected - FVisibleRows + 1;
  end;
  FTop := EnsureRange(FTop, 0, Max(0, Length(FOrder) - FVisibleRows));
end;

function TAtlasCompletionPopupLayout.TagWidth(const ATag: TAtlasTag): Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextWidth(TAtlasCompletionTexts.TagText(ATag)) + Scale(TAtlasDraw.cChipPad);
  Canvas.Font := Font;
end;

function TAtlasCompletionPopupLayout.ItemTags(const AItem: TAtlasCompletionItem): TAtlasTags;
var
  mTag: TAtlasTag;
begin
  Result := nil;
  for mTag in TAtlasItemPresentation.Tags(AItem) do
  begin
    if FOptions.ShowVariantBranch or (mTag.Id <> TAtlasTagId.VariantBranch) then
    begin
      Result := Result + [mTag];
    end;
  end;
end;

function TAtlasCompletionPopupLayout.MeasureWidth: Integer;
var
  mPosition, mCount, mWidest, mWidth: Integer;
  mItem: TAtlasCompletionItem;
  mTag: TAtlasTag;
  mDetail: string;
begin
  // Nur die ersten Einträge messen; eine gezogene Breite (#416) hat Vorrang (ListWidth).
  Canvas.Font := Font;
  mWidest := 0;
  mCount := Min(Length(FOrder), 200);
  for mPosition := 0 to mCount - 1 do
  begin
    if TAtlasRanking.IsHeader(FOrder[mPosition]) then
    begin
      Continue;
    end;
    mItem := FItems[FOrder[mPosition]];
    mWidth := Canvas.TextWidth(mItem.Name);
    mDetail := TAtlasCompletionTexts.DetailText(mItem);
    if mDetail <> '' then
    begin
      Inc(mWidth, Scale(12) + Canvas.TextWidth(mDetail));
    end;
    for mTag in ItemTags(mItem) do
    begin
      Inc(mWidth, Scale(6) + TagWidth(mTag));
    end;
    mWidest := Max(mWidest, mWidth);
  end;
  // Badge (7 + 24 + 9), rechter Rand der Zeile (7), Ränder und Scrollleiste.
  Inc(mWidest, Scale(7 + 24 + 9 + 7) + 2 * Pad + ScrollReserve);
  if TAtlasCompletionSets.Active(FItems) then
  begin
    Inc(mWidest, Scale(cCheckWidth));
  end;
  if FOptions.FavoritesEnabled then
  begin
    Inc(mWidest, Scale(cStarWidth));
  end;
  Canvas.Font := UIFont;
  mWidest := Max(mWidest, Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.FooterKeys) + '    ' +
    TAtlasStrings.Fmt(TAtlasTextId.CountFits, [999, 9999])) + Scale(18));
  Canvas.Font := Font;
  Result := TAtlasPopupWidth.Fit(mWidest, Scale(cMinWidth), Scale(cMaxWidth));
end;

procedure TAtlasCompletionPopupLayout.PlaceAndShow;
begin
  // Nur wachsen, nie schrumpfen, solange die Sitzung läuft (#416).
  FSessionWidth := TAtlasPopupWidth.Grow(FSessionWidth, MeasureWidth);
  Relayout;
end;

procedure TAtlasCompletionPopupLayout.PlaceAt(AListWidth, AHeight: Integer);
var
  mBounds, mArea: TRect;
  mLeft, mWidth: Integer;
begin
  mArea := WorkAreaAt(FAnchor.TopLeft);
  // Die Liste bleibt am Wortanfang; das Panel rechts davon, ohne Platz dort links, ohne Platz auf
  // beiden Seiten eingeklappt (#428).
  mLeft := FAnchor.Left;
  FPanel.AutoCollapsed := False;
  FPanel.Left := False;
  if FPanel.Shown then
  begin
    if mLeft + AListWidth + PanelWidth > mArea.Right then
    begin
      if mLeft - PanelWidth >= mArea.Left then
      begin
        FPanel.Left := True;
      end
      else if not FPanel.Collapsed then
      begin
        FPanel.AutoCollapsed := True;
        FPanel.Left := mLeft + AListWidth + PanelWidth > mArea.Right;
      end;
    end;
  end;
  mWidth := AListWidth + PanelWidth;
  if FPanel.Left then
  begin
    Dec(mLeft, PanelWidth);
  end;
  mBounds := TRect.Create(Point(mLeft, FAnchor.Bottom + 2), mWidth, AHeight);
  // Unten kein Platz: über die Zeile.
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, FAnchor.Top - AHeight - 2);
  end;
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mWidth), mBounds.Top);
  end;
  if mBounds.Top < mArea.Top then
  begin
    mBounds.SetLocation(mBounds.Left, mArea.Top);
  end;
  ShowAt(mBounds);
end;

function TAtlasCompletionPopupLayout.StarAt(AX, AY: Integer): Integer;
var
  mRow: TRect;
begin
  Result := -1;
  if not FOptions.FavoritesEnabled or FEmpty.Showing then
  begin
    Exit;
  end;
  Result := RowAt(AX, AY);
  if (Result < 0) or TAtlasRanking.IsHeader(FOrder[Result]) or
    not TAtlasFavorites.CanPin(FItems[FOrder[Result]]) then
  begin
    Exit(-1);
  end;
  mRow := RowRect(Result - FTop);
  if (AX < mRow.Left) or (AX >= mRow.Left + Scale(cStarWidth + 3)) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasCompletionPopupLayout.WidthsChanged;
begin
  if Assigned(FEvents.OnWidthsChanged) then
  begin
    FEvents.OnWidthsChanged(FManualListWidth, FPanel.Width);
  end;
end;

function TAtlasCompletionPopupLayout.HitArea(AX, AY: Integer): TAtlasHitArea;
var
  mBoundary, mZone: Integer;
begin
  Result := TAtlasHitArea.None;
  mZone := Scale(4);
  if AX >= ClientWidth - mZone then
  begin
    if AY >= ClientHeight - Scale(16) then
    begin
      Result := TAtlasHitArea.Grip;
    end
    else
    begin
      Result := TAtlasHitArea.Edge;
    end;
    Exit;
  end;
  if not FPanel.Shown then
  begin
    Exit;
  end;
  if Collapsed then
  begin
    if PtInRect(PanelRect, Point(AX, AY)) then
    begin
      Result := TAtlasHitArea.PanelBar;
    end;
    Exit;
  end;
  if FPanel.Left then
  begin
    mBoundary := PanelWidth;
  end
  else
  begin
    mBoundary := ListRight;
  end;
  if Abs(AX - mBoundary) <= mZone then
  begin
    Result := TAtlasHitArea.Splitter;
  end;
end;

function TAtlasCompletionPopupLayout.ListState: TAtlasCompletionList;
begin
  Result.Items := FItems;
  Result.Order := FOrder;
  Result.Pattern := FPattern;
  Result.RestFrom := FRestFrom;
  Result.Limited := FOptions.Limited;
  Result.Target := FOptions.Target;
  Result.Notice := FNotice;
end;

end.
