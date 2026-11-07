unit Atlas.UI.Completion.PopupPainter;

// Vervollständigungs-Popup (#410), Stufe Zeichnen: Chips, Warnleiste, Überschriften, Zeilen mit Badge, Name,
// Tags und Detail, Scrollleiste, Fußzeile, leerer Zustand, Detailpanel und Griff; dazu der Tooltip für gekürzte
// Zeilen (#420). Kette und Aussehen: Atlas.UI.Completion.Popup.

interface

uses
  Vcl.Controls,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation,
  Atlas.UI.Completion.PopupState,
  Atlas.UI.Completion.PopupLayout;

type
  TAtlasCompletionPopupPainter = class(TAtlasCompletionPopupLayout)
  protected
    function Dim(AColor: TAtlasColor): TAtlasColor;
    procedure DrawChips;
    procedure DrawSyntax;
    procedure DrawHeader(ARow, APosition: Integer);
    /// <summary>Marke ▸ links in der gewählten Zeile (#447).</summary>
    procedure DrawMarker(const ARow: TRect);
    procedure DrawBadge(const ARow: TRect; const AItem: TAtlasCompletionItem; out ARight: Integer);
    procedure DrawCheck(const ARow: TRect; AChecked: Boolean);
    /// <summary>Stern der Favoriten (#458) links in ARow: gefüllt = angeheftet, sonst nur der Umriss.</summary>
    procedure DrawStar(const ARow: TRect; AFilled: Boolean);
    procedure DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect; ATruncated: Boolean);
    procedure DrawTag(const ATag: TAtlasTag; ALeft: Integer; const ARow: TRect);
    procedure DrawRow(ARow, APosition: Integer);
    /// <summary>Auswahl (#447), Stern (#458) und Kontrollkästchen (#448) links; ARow.Left rückt dahinter.
    /// </summary>
    procedure DrawRowMarks(var ARow: TRect; const AItem: TAtlasCompletionItem; APosition: Integer);
    /// <summary>Detail ganz rechts, Tags davor; liefert den linken Rand der Tags. ATruncated, wenn Detail oder
    /// Tags nicht ganz passen.</summary>
    function DrawRowTail(const ARow: TRect; const AItem: TAtlasCompletionItem; ANameLeft, ANameWidth: Integer;
      out ATruncated: Boolean): Integer;
    /// <summary>Merkt für den Tooltip (#420), ob die sichtbare Zeile ARow gekürzt ist.</summary>
    procedure MarkTruncated(ARow: Integer; ATruncated: Boolean);
    procedure DrawScrollBar;
    procedure DrawFooter(const ALeft, ARight: string);
    /// <summary>Chips, Warnleiste, sichtbare Zeilen, Scrollleiste und Fußzeile.</summary>
    procedure DrawList;
    procedure PaintEmpty;
    procedure PaintPanel;
    procedure DrawGrip;
    procedure Paint; override;
    /// <summary>Sichtbare Zeile unter der Maus, wenn sie ein gekürzter Eintrag ist.</summary>
    function TipRow(out ARow: Integer): Boolean;
    procedure TipTimer(Sender: TObject);
    procedure HideTip;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Sternspalte der Favoriten (#458) zeigen.</summary>
    property FavoritesEnabled: Boolean read FOptions.FavoritesEnabled write FOptions.FavoritesEnabled;
    /// <summary>Gezeigter Hinweis der Fußzeile; '' ohne.</summary>
    property Notice: string read FNotice;
    /// <summary>Gewählte Zeile mit Rahmen und Marke ▸ statt nur farbig (#447, completion.selectionMarker).</summary>
    property SelectionMarker: Boolean read FOptions.SelectionMarker write FOptions.SelectionMarker;
    /// <summary>Gezeigter Hinweis bei unvollständigem Code (#457).</summary>
    property Syntax: TAtlasSyntaxNotice read FSyntax;
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    property ManualListWidth: Integer read FManualListWidth write FManualListWidth;
    /// <summary>Breite des Panels in logischen Pixeln (#416).</summary>
    property PanelWidthSetting: Integer read FPanel.Width write FPanel.Width;
    property PanelCollapsed: Boolean read FPanel.Collapsed write FPanel.Collapsed;
    property OnWidthsChanged: TAtlasWidthsEvent read FEvents.OnWidthsChanged write FEvents.OnWidthsChanged;
    property OnPanelToggled: TAtlasPanelEvent read FEvents.OnPanelToggled write FEvents.OnPanelToggled;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Timing,
  Atlas.UI.Popup.Window,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Strings,
  Atlas.UI.Completion.PopupTexts;

const
  cTextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;

{ TAtlasCompletionPopupPainter }

constructor TAtlasCompletionPopupPainter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTipTimer.OnTimer := TipTimer;
end;

function TAtlasCompletionPopupPainter.Dim(AColor: TAtlasColor): TAtlasColor;
begin
  if FDimRow then
  begin
    Result := TAtlasColorMath.Mix(AColor, Colors.Surface, 0.62);
  end
  else
  begin
    Result := AColor;
  end;
end;

procedure TAtlasCompletionPopupPainter.DrawSyntax;
var
  mBar, mText: TRect;
  mLead, mLineText: string;
  mLeft: Integer;
begin
  FSyntaxLink := Rect(0, 0, 0, 0);
  if SyntaxHeight = 0 then
  begin
    Exit;
  end;
  mBar := Rect(ListLeft + Pad + Scale(4), Pad + ChipsHeight + Scale(2), ListRight - Pad - Scale(4),
    Pad + ChipsHeight + SyntaxHeight - Scale(2));
  FillRounded(mBar, Colors.WarnSoft, TAtlasDraw.cChipRadius);
  mLead := TAtlasCompletionTexts.SyntaxLead(FSyntax.Trust);
  mLineText := TAtlasCompletionTexts.SyntaxLineText(FSyntax.Line);
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(Colors.Warn);
  Canvas.Brush.Style := bsClear;
  mText := Rect(mBar.Left + Scale(8), mBar.Top, mBar.Right - Scale(8), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mLead), -1, mText, cTextFlags or DT_END_ELLIPSIS);
  // Zeilenangabe unterstrichen dahinter; nur sie ist anklickbar.
  mLeft := mText.Left + Canvas.TextWidth(mLead);
  if mLeft + Canvas.TextWidth(mLineText) <= mText.Right then
  begin
    Canvas.Font.Style := [fsUnderline];
    mText.Left := mLeft;
    DrawText(Canvas.Handle, PChar(mLineText), -1, mText, cTextFlags);
    FSyntaxLink := Rect(mLeft, mBar.Top, mLeft + Canvas.TextWidth(mLineText), mBar.Bottom);
    Canvas.Font.Style := [];
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasCompletionPopupPainter.DrawChips;
var
  mChip: TAtlasChip;
  mText: string;
  X, mTop, mHeight: Integer;
  mBox, mTextRect: TRect;
begin
  FChips.Rects := nil;
  FChips.Kinds := nil;
  if ChipsHeight = 0 then
  begin
    Exit;
  end;
  Canvas.Font := UIFont;
  mHeight := Canvas.TextHeight('Wg') + Scale(4);
  mTop := Pad + (ChipsHeight - mHeight) div 2;
  X := ListLeft + Pad + Scale(4);
  for mChip := Low(TAtlasChip) to High(TAtlasChip) do
  begin
    if (mChip <> TAtlasChip.All) and (FChips.Counts[mChip] = 0) then
    begin
      Continue;
    end;
    mText := Format('%s %d', [TAtlasStrings.Text(TAtlasTextId(Ord(TAtlasTextId.ChipAll) + Ord(mChip))),
      FChips.Counts[mChip]]);
    Canvas.Font := UIFont;
    mBox := Rect(X, mTop, X + Canvas.TextWidth(mText) + Scale(14), mTop + mHeight);
    if mBox.Right > ListRight - Pad then
    begin
      Break;
    end;
    if mChip = FChips.Active then
    begin
      FrameRounded(mBox, Colors.Accent, 9, ToColor(Colors.AccentSoft));
      Canvas.Font.Color := ToColor(Colors.Accent);
    end
    else
    begin
      FrameRounded(mBox, Colors.Line, 9);
      Canvas.Font.Color := ToColor(Colors.Muted);
    end;
    Canvas.Brush.Style := bsClear;
    mTextRect := mBox;
    DrawText(Canvas.Handle, PChar(mText), -1, mTextRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    FChips.Rects := FChips.Rects + [mBox];
    FChips.Kinds := FChips.Kinds + [mChip];
    X := mBox.Right + Scale(6);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasCompletionPopupPainter.DrawHeader(ARow, APosition: Integer);
var
  mRow: TRect;
  mText: string;
begin
  mText := TAtlasCompletionTexts.HeaderText(FItems, FOrder, APosition);
  mRow := RowRect(ARow);
  Inc(mRow.Left, Scale(7));
  Canvas.Font := UIFont;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  mRow.Top := mRow.Top + Scale(4);
  DrawText(Canvas.Handle, PChar(mText), -1, mRow, cTextFlags or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
  if ARow >= Length(FTruncated) then
  begin
    SetLength(FTruncated, ARow + 1);
  end;
  FTruncated[ARow] := False;
end;

procedure TAtlasCompletionPopupPainter.DrawFooter(const ALeft, ARight: string);
var
  mFooter, mText: TRect;
begin
  // Nur unter der Liste; das Panel reicht bis unten.
  mFooter := Rect(ListLeft, ClientHeight - FooterHeight, ListRight, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(mFooter);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(mFooter.Left, mFooter.Top);
  Canvas.LineTo(mFooter.Right, mFooter.Top);
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  mText := Rect(mFooter.Left + Scale(9), mFooter.Top + 1, mFooter.Right - Scale(9), mFooter.Bottom);
  DrawText(Canvas.Handle, PChar(ARight), -1, mText, cTextFlags or DT_RIGHT);
  mText.Right := mText.Right - Canvas.TextWidth(ARight) - Scale(10);
  DrawText(Canvas.Handle, PChar(ALeft), -1, mText, cTextFlags or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasCompletionPopupPainter.PaintEmpty;
var
  mLine: TRect;

  procedure DrawLine(AIndex: Integer; const AText: string; AColor: TAtlasColor);
  begin
    mLine := Rect(ListLeft + Pad + Scale(7), ListTop + AIndex * RowHeight, ListRight - Pad - Scale(7),
      ListTop + (AIndex + 1) * RowHeight);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(AText), -1, mLine, cTextFlags or DT_END_ELLIPSIS);
  end;

begin
  DrawSyntax;
  if FEmpty.Prefix <> '' then
  begin
    DrawLine(0, TAtlasStrings.Fmt(TAtlasTextId.NoMatchesFor, [FEmpty.Prefix]), Colors.Text);
  end
  else
  begin
    DrawLine(0, TAtlasStrings.Text(TAtlasTextId.NoSuggestions), Colors.Text);
  end;
  // Unvollständiger Code (#457): statt des Tipps zur Rücktaste der Fehler.
  if (FSyntax.Trust <> TAtlasSyntaxTrust.Sure) and (FSyntax.Message <> '') then
  begin
    DrawLine(1, FSyntax.Message, Colors.Muted);
  end
  else if FEmpty.Prefix <> '' then
  begin
    DrawLine(1, TAtlasStrings.Text(TAtlasTextId.BackspaceWidens), Colors.Muted);
  end;
  Canvas.Brush.Style := bsSolid;
  DrawFooter(TAtlasStrings.Text(TAtlasTextId.EscCloses), TAtlasStrings.Fmt(TAtlasTextId.CountOf, [0, FEmpty.Total]));
end;

procedure TAtlasCompletionPopupPainter.DrawBadge(const ARow: TRect; const AItem: TAtlasCompletionItem;
  out ARight: Integer);
var
  mBadge: TAtlasBadge;
  mBox, mText: TRect;
  mTop: Integer;
begin
  mBadge := TAtlasItemPresentation.Badge(AItem);
  mTop := ARow.Top + (ARow.Height - Scale(17)) div 2;
  mBox := Rect(ARow.Left + Scale(7), mTop, ARow.Left + Scale(7 + 24), mTop + Scale(17));
  FillRounded(mBox, Dim(Colors.Badges[mBadge.Kind].Background), 4);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -Round(mBox.Height * 0.62);
  Canvas.Font.Color := ToColor(Dim(Colors.Badges[mBadge.Kind].Text));
  Canvas.Brush.Style := bsClear;
  mText := mBox;
  DrawText(Canvas.Handle, PChar(mBadge.Code), -1, mText, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Canvas.Font := Font;
  ARight := mBox.Right;
end;

/// <summary>Je Zeichen von AName (1-basiert), ob es zum Getippten APattern gehört.</summary>
function NameMarks(const APattern, AName: string): TArray<Boolean>;
var
  mPosition: Integer;
begin
  SetLength(Result, Length(AName) + 1);
  for mPosition in TAtlasItemPresentation.Highlights(APattern, AName) do
  begin
    if (mPosition >= 1) and (mPosition <= Length(AName)) then
    begin
      Result[mPosition] := True;
    end;
  end;
end;

/// <summary>Letztes Zeichen des Laufs gleicher Hervorhebung ab AStart.</summary>
function RunEnd(const AMarks: TArray<Boolean>; AStart, ALength: Integer): Integer;
begin
  Result := AStart;
  while (Result < ALength) and (AMarks[Result + 1] = AMarks[AStart]) do
  begin
    Inc(Result);
  end;
end;

procedure TAtlasCompletionPopupPainter.DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect;
  ATruncated: Boolean);
var
  mMarks: TArray<Boolean>;
  mIndex, mRun, mX: Integer;
  mPart: TRect;
  mText: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  if ATruncated or (FPattern = '') or FActionRow then
  begin
    // Gekürzt ohne Hervorhebung: Die Positionen passen nicht mehr zur Ellipse.
    if FActionRow then
    begin
      Canvas.Font.Color := ToColor(Colors.Accent);
    end
    else
    begin
      Canvas.Font.Color := ToColor(Dim(Colors.Text));
    end;
    mPart := Rect(ALeft, ARow.Top, ARight, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(AName), -1, mPart, cTextFlags or DT_END_ELLIPSIS);
    Exit;
  end;
  mMarks := NameMarks(FPattern, AName);
  // Läufe gleicher Hervorhebung nacheinander zeichnen.
  mX := ALeft;
  mIndex := 1;
  while mIndex <= Length(AName) do
  begin
    mRun := RunEnd(mMarks, mIndex, Length(AName));
    mText := Copy(AName, mIndex, mRun - mIndex + 1);
    if mMarks[mIndex] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(Dim(Colors.Accent));
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := ToColor(Dim(Colors.Text));
    end;
    mPart := Rect(mX, ARow.Top, ARight, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, cTextFlags);
    Inc(mX, Canvas.TextWidth(mText));
    mIndex := mRun + 1;
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasCompletionPopupPainter.DrawTag(const ATag: TAtlasTag; ALeft: Integer; const ARow: TRect);
var
  mBox, mText: TRect;
  mLine, mTextColor: TAtlasColor;
  mHeight: Integer;
begin
  case ATag.Kind of
    TAtlasTagKind.Accent: begin mLine := Colors.Accent; mTextColor := Colors.Accent; end;
    TAtlasTagKind.Add: begin mLine := Colors.Add; mTextColor := Colors.Add; end;
    TAtlasTagKind.Warn: begin mLine := Colors.Warn; mTextColor := Colors.Warn; end;
    TAtlasTagKind.Error: begin mLine := Colors.Error; mTextColor := Colors.Error; end;
  else
    mLine := Colors.Line;
    mTextColor := Colors.Muted;
  end;
  Canvas.Font := UIFont;
  mHeight := Canvas.TextHeight('Wg') + Scale(2);
  mBox := Rect(ALeft, ARow.Top + (ARow.Height - mHeight) div 2, ALeft + TagWidth(ATag), 0);
  mBox.Bottom := mBox.Top + mHeight;
  Canvas.Font := UIFont;
  // Warnfläche (#481): „verdeckt …“ fällt auch ohne Farbsehen auf.
  if ATag.Filled and (ATag.Kind = TAtlasTagKind.Warn) then
  begin
    FillRounded(mBox, Colors.WarnSoft, TAtlasDraw.cChipRadius);
  end;
  FrameRounded(mBox, mLine, TAtlasDraw.cChipRadius);
  Canvas.Font.Color := ToColor(mTextColor);
  Canvas.Brush.Style := bsClear;
  mText := mBox;
  DrawText(Canvas.Handle, PChar(TAtlasCompletionTexts.TagText(ATag)), -1, mText, DT_CENTER or DT_VCENTER or
    DT_SINGLELINE or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TAtlasCompletionPopupPainter.DrawCheck(const ARow: TRect; AChecked: Boolean);
var
  mBox: TRect;
  mSize, mTop: Integer;
  mPoints: array[0..2] of TPoint;
begin
  mSize := Scale(13);
  mTop := ARow.Top + (ARow.Height - mSize) div 2;
  mBox := Rect(ARow.Left + Scale(7), mTop, ARow.Left + Scale(7) + mSize, mTop + mSize);
  if not AChecked then
  begin
    FrameRounded(mBox, Colors.Muted, 3);
    Exit;
  end;
  FillRounded(mBox, Colors.Accent, 3);
  // Haken in der Flächenfarbe.
  mPoints[0] := Point(mBox.Left + MulDiv(mSize, 3, 13), mBox.Top + MulDiv(mSize, 7, 13));
  mPoints[1] := Point(mBox.Left + MulDiv(mSize, 5, 13), mBox.Top + MulDiv(mSize, 10, 13));
  mPoints[2] := Point(mBox.Left + MulDiv(mSize, 10, 13), mBox.Top + MulDiv(mSize, 3, 13));
  Canvas.Pen.Color := ToColor(Colors.Surface);
  Canvas.Pen.Width := Max(1, Scale(2));
  Canvas.Polyline(mPoints);
  Canvas.Pen.Width := 1;
end;

procedure TAtlasCompletionPopupPainter.DrawStar(const ARow: TRect; AFilled: Boolean);
var
  mPoints: array[0..9] of TPoint;
  mIndex, mRadius, mOuter, mInner, mCenterX, mCenterY: Integer;
  mAngle: Double;
begin
  // Fünfzackiger Stern, Spitze oben: abwechselnd äußerer und innerer Radius.
  mOuter := Scale(6);
  mInner := Max(1, Round(mOuter * 0.45));
  mCenterX := ARow.Left + Scale(4) + mOuter;
  mCenterY := ARow.Top + ARow.Height div 2;
  for mIndex := 0 to 9 do
  begin
    if Odd(mIndex) then
    begin
      mRadius := mInner;
    end
    else
    begin
      mRadius := mOuter;
    end;
    mAngle := -Pi / 2 + mIndex * Pi / 5;
    mPoints[mIndex] := Point(mCenterX + Round(mRadius * Cos(mAngle)), mCenterY + Round(mRadius * Sin(mAngle)));
  end;
  Canvas.Pen.Width := 1;
  if AFilled then
  begin
    Canvas.Pen.Color := ToColor(Dim(Colors.Accent));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Dim(Colors.Accent));
  end
  else
  begin
    Canvas.Pen.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
  end;
  Canvas.Polygon(mPoints);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasCompletionPopupPainter.DrawRow(ARow, APosition: Integer);
var
  mItem: TAtlasCompletionItem;
  mRow: TRect;
  mNameLeft, mNameWidth, mGap, mX: Integer;
  mTruncated: Boolean;
begin
  mItem := FItems[FOrder[APosition]];
  mRow := RowRect(ARow);
  // Geerbte Member mit 62 % Deckkraft (#419); die gewählte Zeile bleibt voll lesbar.
  // Geerbt (#419) bzw. in der aktiven Konfiguration nicht vorhanden (#476): 62 % Deckkraft.
  // Rest ohne Treffer (#497) ebenso.
  FDimRow := ((FOptions.DimInherited and (mItem.Depth > 0)) or mItem.Unavailable or ((FRestFrom >= 0) and
    (APosition > FRestFrom))) and (APosition <> FSelected);
  DrawRowMarks(mRow, mItem, APosition);
  DrawBadge(mRow, mItem, mNameLeft);
  Inc(mNameLeft, Scale(9));
  mGap := Scale(6);
  // Breiten: Name, Tags, Detail; zu lang: erst das Detail kürzen bzw. weglassen, dann den Namen.
  Canvas.Font := Font;
  mNameWidth := Canvas.TextWidth(mItem.Name);
  mX := DrawRowTail(mRow, mItem, mNameLeft, mNameWidth, mTruncated);
  // Aktionen (#444, #471) und Hinweise (#466) in Akzentfarbe.
  FActionRow := mItem.IsAction or mItem.Hint;
  DrawName(mItem.Name, mNameLeft, Max(mNameLeft, mX - mGap), mRow, mNameLeft + mNameWidth > mX - mGap);
  FActionRow := False;
  Canvas.Brush.Style := bsSolid;
  MarkTruncated(ARow, mTruncated or (mNameLeft + mNameWidth > mX - mGap));
  FDimRow := False;
end;

procedure TAtlasCompletionPopupPainter.DrawRowMarks(var ARow: TRect; const AItem: TAtlasCompletionItem;
  APosition: Integer);
begin
  if APosition = FSelected then
  begin
    FillRounded(ARow, Colors.Selection, 4);
    // Nicht nur Farbe (#447): Rahmen in Akzentfarbe und Marke im Rand vor dem Badge.
    if FOptions.SelectionMarker then
    begin
      FrameRounded(ARow, Colors.Accent, 4);
      DrawMarker(ARow);
    end;
  end;
  // Favoriten (#458): gefüllter Stern bei angehefteten Einträgen, leerer beim Überfahren.
  if FOptions.FavoritesEnabled then
  begin
    if AItem.Favorite then
    begin
      DrawStar(ARow, True);
    end
    else if (APosition = FHoverPosition) and TAtlasFavorites.CanPin(AItem) then
    begin
      DrawStar(ARow, False);
    end;
    Inc(ARow.Left, Scale(cStarWidth));
  end;
  // Mengenmodus (#448): Kontrollkästchen vor dem Badge.
  if AItem.SetOf <> '' then
  begin
    DrawCheck(ARow, AItem.Checked);
    Inc(ARow.Left, Scale(cCheckWidth));
  end;
end;

function TAtlasCompletionPopupPainter.DrawRowTail(const ARow: TRect; const AItem: TAtlasCompletionItem;
  ANameLeft, ANameWidth: Integer; out ATruncated: Boolean): Integer;
var
  mTags: TAtlasTags;
  mTag: TAtlasTag;
  mDetail: string;
  mPart: TRect;
  mRight, mGap, mTagsWidth, mDetailWidth: Integer;
begin
  mRight := ARow.Right - Scale(7);
  mGap := Scale(6);
  mTags := ItemTags(AItem);
  mTagsWidth := 0;
  for mTag in mTags do
  begin
    Inc(mTagsWidth, TagWidth(mTag) + mGap);
  end;
  mDetail := TAtlasCompletionTexts.DetailText(AItem);
  Canvas.Font := Font;
  mDetailWidth := 0;
  if mDetail <> '' then
  begin
    mDetailWidth := Min(Canvas.TextWidth(mDetail), mRight - ANameLeft - ANameWidth - mTagsWidth - Scale(12));
    if mDetailWidth < Scale(40) then
    begin
      mDetailWidth := 0;
    end;
  end;
  ATruncated := (mDetail <> '') and (mDetailWidth < Canvas.TextWidth(mDetail));
  // Rechts: Detail ganz außen, Tags davor.
  Result := mRight;
  if mDetailWidth > 0 then
  begin
    mPart := Rect(Result - mDetailWidth, ARow.Top, Result, ARow.Bottom);
    Canvas.Font.Color := ToColor(Dim(Colors.Muted));
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mDetail), -1, mPart, cTextFlags or DT_END_ELLIPSIS);
    Dec(Result, mDetailWidth + mGap);
  end;
  for mTag in mTags do
  begin
    Dec(Result, TagWidth(mTag));
    if Result < ANameLeft + Scale(40) then
    begin
      ATruncated := True;
      Break;
    end;
    DrawTag(mTag, Result, ARow);
    Dec(Result, mGap);
  end;
end;

procedure TAtlasCompletionPopupPainter.MarkTruncated(ARow: Integer; ATruncated: Boolean);
begin
  if ARow >= Length(FTruncated) then
  begin
    SetLength(FTruncated, ARow + 1);
  end;
  FTruncated[ARow] := ATruncated;
end;

procedure TAtlasCompletionPopupPainter.DrawMarker(const ARow: TRect);
var
  mLeft, mMiddle, mHalf: Integer;
begin
  // Schmales Dreieck im Rand vor dem Badge bzw. Stern; passt auch neben die Sternspalte.
  mLeft := ARow.Left + Scale(1);
  mMiddle := (ARow.Top + ARow.Bottom) div 2;
  mHalf := Scale(4);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Accent);
  Canvas.Pen.Color := ToColor(Colors.Accent);
  Canvas.Polygon([Point(mLeft, mMiddle - mHalf), Point(mLeft + Scale(3), mMiddle), Point(mLeft, mMiddle + mHalf)]);
end;

procedure TAtlasCompletionPopupPainter.DrawScrollBar;
var
  mTrack, mThumb: TRect;
  mTotal, mVisible, mThumbHeight, mThumbTop: Integer;
begin
  mTotal := Length(FOrder);
  mVisible := RowCount;
  if mTotal <= mVisible then
  begin
    Exit;
  end;
  mTrack := Rect(ListRight - Pad - Scale(5), ListTop + Scale(2), ListRight - Pad - Scale(1),
    ListTop + mVisible * RowHeight - Scale(2));
  mThumbHeight := Max(Scale(16), mTrack.Height * mVisible div mTotal);
  mThumbTop := mTrack.Top + (mTrack.Height - mThumbHeight) * FTop div Max(1, mTotal - mVisible);
  mThumb := Rect(mTrack.Left, mThumbTop, mTrack.Right, mThumbTop + mThumbHeight);
  TAtlasDraw.Thumb(Canvas, mThumb, Colors, Scale(2));
end;

procedure TAtlasCompletionPopupPainter.Paint;
var
  mTimings: TAtlasQueryTimings;
  mStamp: Int64;
begin
  mTimings := nil;
  mStamp := 0;
  if TAtlasQueryTimings.Enabled then
  begin
    mTimings := TAtlasQueryTimings.Shared;
    mStamp := TAtlasQueryTimings.Stamp;
  end;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  if FEmpty.Showing then
  begin
    PaintEmpty;
  end
  else
  begin
    DrawList;
  end;
  if FPanel.Shown then
  begin
    PaintPanel;
  end;
  DrawGrip;
  PaintBorder;
  if mTimings <> nil then
  begin
    mTimings.Drawn(TAtlasQueryTimings.MsSince(mStamp));
  end;
end;

procedure TAtlasCompletionPopupPainter.DrawList;
var
  mRow: Integer;
  mFooter: TAtlasCompletionFooter;
begin
  DrawChips;
  DrawSyntax;
  for mRow := 0 to RowCount - 1 do
  begin
    if FTop + mRow < Length(FOrder) then
    begin
      if TAtlasRanking.IsHeader(FOrder[FTop + mRow]) then
      begin
        DrawHeader(mRow, FTop + mRow);
      end
      else
      begin
        DrawRow(mRow, FTop + mRow);
      end;
    end;
  end;
  DrawScrollBar;
  mFooter := TAtlasCompletionTexts.Footer(ListState);
  DrawFooter(mFooter.Left, mFooter.Right);
end;

procedure TAtlasCompletionPopupPainter.PaintPanel;
var
  mPanel, mBar: TRect;
  mEdge: Integer;
  mArrow: string;
begin
  mPanel := PanelRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(mPanel);
  // Trennlinie zur Liste.
  if FPanel.Left then
  begin
    mEdge := mPanel.Right - 1;
  end
  else
  begin
    mEdge := mPanel.Left;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(mEdge, 0);
  Canvas.LineTo(mEdge, ClientHeight);
  if Collapsed then
  begin
    // Schmale Leiste (#428): Pfeil zeigt, wohin das Panel aufklappt.
    Canvas.Font := UIFont;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.Brush.Style := bsClear;
    mBar := Rect(mPanel.Left, Scale(6), mPanel.Right, Scale(6) + Canvas.TextHeight('Wg'));
    if FPanel.Left then
    begin
      mArrow := '‹';
    end
    else
    begin
      mArrow := '›';
    end;
    DrawText(Canvas.Handle, PChar(mArrow), -1, mBar, DT_CENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Font.Style := [];
  end
  else
  begin
    // Höher als das Popup: nur die Doku scrollt (#654).
    FDetailView.MaxHeight := ClientHeight;
    FDetailView.Render(Canvas, Colors, Font, UIFont, mPanel, PPI, True);
  end;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasCompletionPopupPainter.DrawGrip;
var
  mRow, mColumn, mSize, mStep, mRight, mBottom: Integer;
begin
  // Punktmuster unten rechts (#416): drei Reihen, nach unten rechts dichter.
  mSize := Max(1, Scale(2));
  mStep := Scale(4);
  mRight := ClientWidth - Scale(4);
  mBottom := ClientHeight - Scale(4);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(TAtlasColorMath.Mix(Colors.Muted, Colors.Surface, 0.6));
  for mRow := 0 to 2 do
  begin
    for mColumn := 0 to 2 - mRow do
    begin
      Canvas.FillRect(Rect(mRight - (mColumn + 1) * mStep + mStep - mSize, mBottom - (mRow + 1) * mStep + mStep - mSize,
        mRight - mColumn * mStep, mBottom - mRow * mStep));
    end;
  end;
end;

procedure TAtlasCompletionPopupPainter.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  HideTip;
  if FOptions.FavoritesEnabled and (FHoverPosition >= 0) then
  begin
    Invalidate;
  end;
  FHoverPosition := -1;
end;

procedure TAtlasCompletionPopupPainter.HideTip;
begin
  FTipTimer.Enabled := False;
  FTip.HidePopup;
end;

function TAtlasCompletionPopupPainter.TipRow(out ARow: Integer): Boolean;
begin
  ARow := FHoverPosition - FTop;
  Result := IsShown and (FHoverPosition >= 0) and (FHoverPosition < Length(FOrder)) and (ARow >= 0) and
    (ARow < Length(FTruncated));
  Result := Result and FTruncated[ARow] and not TAtlasRanking.IsHeader(FOrder[FHoverPosition]);
end;

procedure TAtlasCompletionPopupPainter.TipTimer(Sender: TObject);
var
  mRow: Integer;
  mItem: TAtlasCompletionItem;
  mArea: TRect;
begin
  FTipTimer.Enabled := False;
  if not TipRow(mRow) then
  begin
    Exit;
  end;
  mItem := FItems[FOrder[FHoverPosition]];
  FTip.Colors := Colors;
  FTip.SetScaling(PPI, 1, Font.Name, Font.Size);
  mArea := RowRect(mRow);
  FTip.ShowText(TAtlasCompletionTexts.TipText(mItem, ItemTags(mItem)),
    ClientToScreen(Point(mArea.Left, mArea.Bottom + Scale(2))));
end;

end.
