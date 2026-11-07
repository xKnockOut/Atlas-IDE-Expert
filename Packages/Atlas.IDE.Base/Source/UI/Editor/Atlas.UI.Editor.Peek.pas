unit Atlas.UI.Editor.Peek;

// Fenster für Definition und Referenzen einblenden (#505), nur VCL:
// - Nimmt dem Editor nie den Fokus (TAtlasPopupWindow, #410); Tasten kommen
//   über den Tastatur-Hook aus Atlas.IDE.Results.Peek.
// - Kopfzeile mit Titel und Tastenhinweis, bei mehreren Zielen links eine
//   Liste (Datei:Zeile, darunter der Auszug), rechts der Ausschnitt mit
//   Zeilennummern, Syntaxfarben (TAtlasSyntax.LineTokens), Editorschrift und
//   Zoom (#445). Die Zielzeile ist hinterlegt, der Name darin hervorgehoben;
//   vor der Implementierung steht eine Trennzeile mit Datei und Zeile.
// - Klick in die Liste wählt, Doppelklick öffnet (OnOpen).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Editor.Peek,
  Atlas.UI.Popup.Window;

type
  TAtlasPeekWindow = class(TAtlasPopupWindow)
  private
    FView: TAtlasPeekView;
    FTokens: TArray<TAtlasTokens>;
    FTokensOf: Integer;
    FOnOpen: TNotifyEvent;
    function RowHeight: Integer;
    function HeaderHeight: Integer;
    function ListWidth: Integer;
    function EntryHeight: Integer;
    function CodeRect: TRect;
    procedure UpdatePage;
    procedure PrepareTokens;
    procedure PaintHeader;
    procedure PaintList;
    procedure PaintCode;
    /// <summary>Trennzeile „Implementierung in …“ zu ARow im Rechteck ARect.</summary>
    procedure PaintSeparator(const ARow: TAtlasPeekRow; const ARect: TRect; AGutter: Integer);
    /// <summary>Codezeile AIndex mit Zeilennummer im Rechteck ARect.</summary>
    procedure PaintCodeRow(AIndex: Integer; const ARow: TAtlasPeekRow; const ARect: TRect; AGutter: Integer);
    /// <summary>Lage im Ausschnitt am rechten Rand von AArea, wenn ARowCount Zeilen nicht ins Fenster passen.</summary>
    procedure PaintThumb(const AArea: TRect; ARowCount: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Übernimmt AView (gibt das vorige frei) und zeigt es an ABounds (Bildschirm).</summary>
    procedure ShowView(AView: TAtlasPeekView; const ABounds: TRect);
    /// <summary>Schließt und gibt den Zustand frei.</summary>
    procedure Dismiss;
    /// <summary>Höhe des Fensters für ALines Codezeilen in der aktuellen Schrift.</summary>
    function HeightForLines(ALines: Integer): Integer;
    /// <summary>Nach einer Änderung an View (Auswahl, Scrollen) neu zeichnen.</summary>
    procedure ViewChanged;
    /// <summary>Eintrag der Liste an der Stelle (Client); -1 außerhalb.</summary>
    function EntryAt(const APoint: TPoint): Integer;
    property View: TAtlasPeekView read FView;
    /// <summary>Doppelklick in Liste oder Ausschnitt: die gewählte Stelle öffnen.</summary>
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Styled,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 8;
  cListMax = 300;

{ TAtlasPeekWindow }

constructor TAtlasPeekWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTokensOf := -1;
  SetAccessible(cUiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand));
end;

destructor TAtlasPeekWindow.Destroy;
begin
  FreeAndNil(FView);
  inherited Destroy;
end;

procedure TAtlasPeekWindow.ShowView(AView: TAtlasPeekView; const ABounds: TRect);
begin
  if AView <> FView then
  begin
    FView.Free;
    FView := AView;
  end;
  FTokensOf := -1;
  FTokens := nil;
  ShowAt(ABounds);
  UpdatePage;
  Invalidate;
  if FView <> nil then
  begin
    Announce(FView.Title);
  end;
end;

procedure TAtlasPeekWindow.Dismiss;
begin
  HidePopup;
  FreeAndNil(FView);
  FTokens := nil;
  FTokensOf := -1;
end;

function TAtlasPeekWindow.RowHeight: Integer;
begin
  Canvas.Font.Assign(Font);
  Result := Canvas.TextHeight('Wg') + Scale(2);
end;

function TAtlasPeekWindow.HeaderHeight: Integer;
begin
  Canvas.Font.Assign(UIFont);
  Result := Canvas.TextHeight('Wg') + Scale(2 * 5);
end;

function TAtlasPeekWindow.EntryHeight: Integer;
begin
  Canvas.Font.Assign(UIFont);
  Result := 2 * Canvas.TextHeight('Wg') + Scale(8);
end;

function TAtlasPeekWindow.ListWidth: Integer;
begin
  Result := 0;
  if (FView <> nil) and (FView.Count > 1) then
  begin
    Result := Min(Scale(cListMax), ClientWidth div 3);
  end;
end;

function TAtlasPeekWindow.CodeRect: TRect;
begin
  Result := Rect(ListWidth + 1, HeaderHeight + 1, ClientWidth - 1, ClientHeight - 1);
end;

function TAtlasPeekWindow.HeightForLines(ALines: Integer): Integer;
begin
  Result := HeaderHeight + 2 + Max(1, ALines) * RowHeight;
end;

procedure TAtlasPeekWindow.UpdatePage;
begin
  if FView = nil then
  begin
    Exit;
  end;
  FView.PageRows := Max(1, CodeRect.Height div Max(1, RowHeight));
end;

procedure TAtlasPeekWindow.Resize;
begin
  inherited;
  UpdatePage;
end;

procedure TAtlasPeekWindow.ViewChanged;
begin
  UpdatePage;
  Invalidate;
  if (FView <> nil) and (FView.Count > 0) then
  begin
    Announce(ExtractFileName(FView.Current.Target.Place.FileName) + ' ' + FView.Current.Excerpt);
  end;
end;

procedure TAtlasPeekWindow.PrepareTokens;
var
  mRows: TArray<TAtlasPeekRow>;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  if (FView = nil) or (FView.Count = 0) or (FTokensOf = FView.Selected) then
  begin
    Exit;
  end;
  mRows := FView.Current.Rows;
  SetLength(mLines, Length(mRows));
  for mIndex := 0 to High(mRows) do
  begin
    mLines[mIndex] := mRows[mIndex].Text;
  end;
  FTokens := TAtlasSyntax.LineTokens(mLines);
  FTokensOf := FView.Selected;
end;

function TAtlasPeekWindow.EntryAt(const APoint: TPoint): Integer;
begin
  Result := -1;
  if (FView = nil) or (ListWidth = 0) or (APoint.X >= ListWidth) or (APoint.Y < HeaderHeight) then
  begin
    Exit;
  end;
  Result := (APoint.Y - HeaderHeight) div EntryHeight;
  if Result >= FView.Count then
  begin
    Result := -1;
  end;
end;

procedure TAtlasPeekWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mIndex := EntryAt(Point(X, Y));
  if (mIndex >= 0) and (mIndex <> FView.Selected) then
  begin
    FView.Select(mIndex);
    ViewChanged;
  end;
end;

procedure TAtlasPeekWindow.DblClick;
begin
  inherited;
  if Assigned(FOnOpen) and (FView <> nil) and (FView.Count > 0) then
  begin
    FOnOpen(Self);
  end;
end;

procedure TAtlasPeekWindow.PaintHeader;
var
  mArea: TRect;
  mKeysHint: string;
  mHintWidth: Integer;
begin
  mArea := Rect(0, 0, ClientWidth, HeaderHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(mArea);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(0, mArea.Bottom);
  Canvas.LineTo(ClientWidth, mArea.Bottom);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(UIFont);
  mKeysHint := TAtlasStrings.Text(TAtlasTextId.PeekKeysHint);
  Canvas.Font.Color := ToColor(Colors.Muted);
  mHintWidth := Canvas.TextWidth(mKeysHint);
  mArea.Inflate(-Scale(cPad), 0);
  if mHintWidth < mArea.Width div 2 then
  begin
    DrawText(Canvas.Handle, PChar(mKeysHint), Length(mKeysHint), mArea,
      DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Dec(mArea.Right, mHintWidth + Scale(cPad));
  end;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Font.Style := [fsBold];
  if FView <> nil then
  begin
    DrawText(Canvas.Handle, PChar(FView.Title), Length(FView.Title), mArea,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Canvas.Font.Style := [];
end;

procedure TAtlasPeekWindow.PaintList;
var
  mWidth, mHeight, mIndex, mTop, mHalf: Integer;
  mArea, mLine: TRect;
  mEntry: TAtlasPeekEntry;
  mPlace: string;
begin
  mWidth := ListWidth;
  if mWidth = 0 then
  begin
    Exit;
  end;
  mHeight := EntryHeight;
  mArea := Rect(0, HeaderHeight + 1, mWidth, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(mArea);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(mWidth, mArea.Top);
  Canvas.LineTo(mWidth, ClientHeight);
  Canvas.Font.Assign(UIFont);
  mHalf := Canvas.TextHeight('Wg');
  // Die gewählte Zeile bleibt sichtbar: bei langen Listen weiterschieben.
  mTop := 0;
  if (FView.Selected + 1) * mHeight > mArea.Height then
  begin
    mTop := FView.Selected - mArea.Height div mHeight + 1;
  end;
  for mIndex := mTop to FView.Count - 1 do
  begin
    mLine := Rect(0, mArea.Top + (mIndex - mTop) * mHeight, mWidth, mArea.Top + (mIndex - mTop + 1) * mHeight);
    if mLine.Top >= ClientHeight then
    begin
      Break;
    end;
    mEntry := FView.Entry(mIndex);
    if mIndex = FView.Selected then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Selection);
      Canvas.FillRect(mLine);
    end;
    Canvas.Brush.Style := bsClear;
    mLine.Inflate(-Scale(cPad), 0);
    mPlace := Format('%s:%d', [ExtractFileName(mEntry.Target.Place.FileName), mEntry.Target.Place.Line + 1]);
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.Font.Style := [fsBold];
    mLine.Top := mLine.Top + Scale(4);
    mLine.Bottom := mLine.Top + mHalf;
    DrawText(Canvas.Handle, PChar(mPlace), Length(mPlace), mLine,
      DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Canvas.Font.Color := ToColor(Colors.Muted);
    mLine.Offset(0, mHalf);
    DrawText(Canvas.Handle, PChar(mEntry.Excerpt), Length(mEntry.Excerpt), mLine,
      DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
end;

procedure TAtlasPeekWindow.PaintCode;
var
  mArea, mRow: TRect;
  mRows: TArray<TAtlasPeekRow>;
  mHeight, mIndex, mGutter: Integer;
begin
  mArea := CodeRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(mArea);
  if (FView = nil) or (FView.Count = 0) then
  begin
    Exit;
  end;
  PrepareTokens;
  mRows := FView.Current.Rows;
  mHeight := RowHeight;
  Canvas.Font.Assign(Font);
  mGutter := Canvas.TextWidth('99999') + Scale(cPad);
  for mIndex := FView.Top to Min(High(mRows), FView.Top + FView.PageRows - 1) do
  begin
    mRow := Rect(mArea.Left, mArea.Top + (mIndex - FView.Top) * mHeight, mArea.Right,
      mArea.Top + (mIndex - FView.Top + 1) * mHeight);
    if mRows[mIndex].Target then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Selection);
      Canvas.FillRect(mRow);
    end;
    Canvas.Brush.Style := bsClear;
    if mRows[mIndex].Kind = TAtlasPeekRowKind.Separator then
    begin
      PaintSeparator(mRows[mIndex], mRow, mGutter);
    end
    else
    begin
      PaintCodeRow(mIndex, mRows[mIndex], mRow, mGutter);
    end;
  end;
  PaintThumb(mArea, Length(mRows));
end;

procedure TAtlasPeekWindow.PaintSeparator(const ARow: TAtlasPeekRow; const ARect: TRect; AGutter: Integer);
var
  mValue: string;
  mNumber: TRect;
begin
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(ARect.Left + Scale(cPad), ARect.CenterPoint.Y);
  Canvas.LineTo(ARect.Right - Scale(cPad), ARect.CenterPoint.Y);
  Canvas.Font.Assign(UIFont);
  Canvas.Font.Color := ToColor(Colors.Muted);
  mValue := ' ' + TAtlasStrings.Fmt(TAtlasTextId.PeekImplementation, [ExtractFileName(ARow.FileName), ARow.Line + 1]) +
    ' ';
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  mNumber := Rect(ARect.Left + AGutter, ARect.Top, ARect.Left + AGutter + Canvas.TextWidth(mValue), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(mValue), Length(mValue), mNumber, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
end;

procedure TAtlasPeekWindow.PaintCodeRow(AIndex: Integer; const ARow: TAtlasPeekRow; const ARect: TRect;
  AGutter: Integer);
var
  mNumber: TRect;
  mValue: string;
  mStyled: TAtlasStyledText;
  mX: Integer;
begin
  // Zeilennummer, 1-basiert wie im Editor.
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(Colors.Muted);
  mNumber := Rect(ARect.Left, ARect.Top, ARect.Left + AGutter - Scale(cPad div 2), ARect.Bottom);
  mValue := IntToStr(ARow.Line + 1);
  DrawText(Canvas.Handle, PChar(mValue), Length(mValue), mNumber, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
  mStyled := TAtlasStyledText.Create(ARow.Text);
  if AIndex <= High(FTokens) then
  begin
    mStyled.Tokens := FTokens[AIndex];
  end;
  mStyled.MutedRanges := nil;
  mStyled.ActiveStart := ARow.NameStart;
  mStyled.ActiveStop := ARow.NameStop;
  mStyled.ActiveFill := True;
  mX := ARect.Left + AGutter;
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(Colors.Text);
  mStyled.Draw(TAtlasStyledTarget.Create(Canvas, Colors, Scale(3)), Point(0, Length(mStyled.Text)), mX, ARect, False);
end;

procedure TAtlasPeekWindow.PaintThumb(const AArea: TRect; ARowCount: Integer);
var
  mThumb, mThumbTop: Integer;
begin
  if ARowCount <= FView.PageRows then
  begin
    Exit;
  end;
  mThumb := Max(Scale(12), AArea.Height * FView.PageRows div ARowCount);
  mThumbTop := AArea.Top + (AArea.Height - mThumb) * FView.Top div Max(1, FView.MaxTop);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(TAtlasColorMath.Mix(Colors.Muted, Colors.Surface, cAtlasMixThumb));
  Canvas.FillRect(Rect(AArea.Right - Scale(4), mThumbTop, AArea.Right - Scale(1), mThumbTop + mThumb));
end;

procedure TAtlasPeekWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  PaintHeader;
  PaintList;
  PaintCode;
  PaintBorder;
end;

end.
