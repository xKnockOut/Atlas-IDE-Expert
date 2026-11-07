unit Atlas.UI.Popup.TitledTip;

// Tooltip mit Titel und Text für Symbole in Rinne, Übersichtsleiste und
// Atlas-Spalte (zuerst für persönliche Notizen, #545; bis #1455
// Atlas.UI.Notes.Tip): oben gedämpft „Notiz vom 15.10.2026“, darunter der Text, auch
// mehrzeilig, umbrochen auf höchstens MaxWidth logische Pixel. Ohne Fokus wie
// alle Atlas-Fenster (TAtlasPopupWindow), Schrift der Oberfläche.
// Unter dem Text optional Links, je einer pro Zeile in der Akzentfarbe (etwa
// die Methoden einer Rekursionskette, #623); ein Klick meldet ihre Nummer an
// OnLink.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.UI.Popup.Window;

type
  TAtlasTitledTip = class(TAtlasPopupWindow)
  public const
    /// <summary>Höchstbreite des Textes in logischen Pixeln (96 dpi).</summary>
    cMaxWidth = 420;
    cPadding = 9;
  private
    FTitle: string;
    FText: string;
    FLinks: TArray<string>;
    FLinkRects: TArray<TRect>;
    FOnLink: TProc<Integer>;
    FBodyHeight: Integer;
    function TextFlags: Cardinal;
    function MeasureText(AWidth: Integer): TRect;
    /// <summary>Zeile der Überschrift; dieselbe Lage beim Messen und Zeichnen.</summary>
    function TitleArea(AClientWidth: Integer): TRect;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt Überschrift und Text mit der linken oberen Ecke an APoint (Bildschirmkoordinaten).</summary>
    procedure ShowNote(const ATitle, AText: string; const APoint: TPoint); overload;
    /// <summary>Wie oben, darunter ALinks (je eine Zeile, anklickbar über OnLink).</summary>
    procedure ShowNote(const ATitle, AText: string; const ALinks: TArray<string>; const APoint: TPoint); overload;
    /// <summary>Größe für ATitle und AText (ohne zu zeigen), für Tests.</summary>
    function Measure(const ATitle, AText: string): TSize; overload;
    function Measure(const ATitle, AText: string; const ALinks: TArray<string>): TSize; overload;
    /// <summary>Nummer des Links unter X/Y (Client-Koordinaten nach dem Zeichnen); -1 ohne.</summary>
    function LinkAt(AX, AY: Integer): Integer;
    /// <summary>Bereich des Textes in einem Tooltip der Größe ASize (#1281: Messen und Zeichnen teilen die Lage,
    /// sonst fehlten unten zwei Pixel und die letzte Zeile wurde abgeschnitten).</summary>
    function BodyArea(const ASize: TSize): TRect;
    /// <summary>Höhe des umbrochenen Textes aus dem letzten Measure.</summary>
    property BodyHeight: Integer read FBodyHeight;
    property Title: string read FTitle;
    property Text: string read FText;
    property Links: TArray<string> read FLinks;
    /// <summary>Klick auf einen Link (Nummer ab 0).</summary>
    property OnLink: TProc<Integer> read FOnLink write FOnLink;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Accessibility;

{ TAtlasTitledTip }

constructor TAtlasTitledTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Notes;
end;

function TAtlasTitledTip.TextFlags: Cardinal;
begin
  Result := DT_LEFT or DT_TOP or DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS;
end;

function TAtlasTitledTip.MeasureText(AWidth: Integer): TRect;
var
  mShown: string;
begin
  mShown := FText;
  if mShown = '' then
  begin
    mShown := ' ';
  end;
  Result := Rect(0, 0, AWidth, 0);
  Canvas.Font := UIFont;
  DrawText(Canvas.Handle, PChar(mShown), -1, Result, TextFlags or DT_CALCRECT);
end;

function TAtlasTitledTip.TitleArea(AClientWidth: Integer): TRect;
begin
  Canvas.Font := UIFont;
  Result := Rect(Scale(cPadding), Scale(cPadding) - Scale(2), AClientWidth - Scale(cPadding),
    Scale(cPadding) - Scale(2) + Canvas.TextHeight('Wg'));
end;

function TAtlasTitledTip.BodyArea(const ASize: TSize): TRect;
begin
  Result := Rect(Scale(cPadding), TitleArea(ASize.cx).Bottom + Scale(4), ASize.cx - Scale(cPadding),
    ASize.cy - Scale(cPadding));
end;

function TAtlasTitledTip.Measure(const ATitle, AText: string): TSize;
begin
  Result := Measure(ATitle, AText, nil);
end;

function TAtlasTitledTip.Measure(const ATitle, AText: string; const ALinks: TArray<string>): TSize;
var
  mBody: TRect;
  mTitleWidth, mWidth, mLinkWidth, mLineHeight: Integer;
  mLink: string;
begin
  FTitle := ATitle;
  FLinks := ALinks;
  FLinkRects := nil;
  // Zeilenumbrüche der Notiz als Windows-Umbrüche, damit DrawText sie einhält.
  FText := AText.Replace(#13#10, #10).Replace(#10, #13#10);
  Canvas.Font := UIFont;
  mTitleWidth := Canvas.TextWidth(FTitle);
  mBody := MeasureText(Scale(cMaxWidth));
  FBodyHeight := mBody.Height;
  mWidth := Max(mTitleWidth, mBody.Width);
  mLineHeight := Canvas.TextHeight('Wg');
  for mLink in FLinks do
  begin
    mLinkWidth := Canvas.TextWidth(mLink);
    if mLinkWidth > mWidth then
    begin
      mWidth := mLinkWidth;
    end;
  end;
  Result.cx := Min(mWidth, Scale(cMaxWidth)) + 2 * Scale(cPadding);
  // Wie TitleArea und BodyArea: Überschrift ab Padding - 2, Abstand 4, Text, Padding unten.
  Result.cy := TitleArea(Result.cx).Bottom + Scale(4) + mBody.Height + Scale(cPadding);
  if Length(FLinks) > 0 then
  begin
    Inc(Result.cy, Scale(6) + Length(FLinks) * (mLineHeight + Scale(2)));
  end;
end;

procedure TAtlasTitledTip.ShowNote(const ATitle, AText: string; const APoint: TPoint);
begin
  ShowNote(ATitle, AText, nil, APoint);
end;

procedure TAtlasTitledTip.ShowNote(const ATitle, AText: string; const ALinks: TArray<string>; const APoint: TPoint);
var
  mArea, mBounds: TRect;
  mSize: TSize;
begin
  mSize := Measure(ATitle, AText, ALinks);
  mArea := WorkAreaAt(APoint);
  mSize.cx := Min(mSize.cx, mArea.Width);
  mSize.cy := Min(mSize.cy, mArea.Height);
  mBounds := TRect.Create(APoint, mSize.cx, mSize.cy);
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mSize.cx), mBounds.Top);
  end;
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, Max(mArea.Top, mArea.Bottom - mSize.cy));
  end;
  SetAccessible(cUiaToolTipControlType, ATitle);
  ShowAt(mBounds);
  Invalidate;
  if Length(ALinks) > 0 then
  begin
    Announce(ATitle + '. ' + AText + '. ' + string.Join(', ', ALinks));
  end
  else
  begin
    Announce(ATitle + '. ' + AText);
  end;
end;

function TAtlasTitledTip.LinkAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FLinkRects) do
  begin
    if PtInRect(FLinkRects[mIndex], Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasTitledTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  mIndex := LinkAt(X, Y);
  if (Button = mbLeft) and (mIndex >= 0) and Assigned(FOnLink) then
  begin
    TAtlasGuard.Run(GuardFeature,
      procedure
      begin
        FOnLink(mIndex);
      end);
  end;
end;

procedure TAtlasTitledTip.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if LinkAt(X, Y) >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

procedure TAtlasTitledTip.Paint;
var
  mArea, mLinkArea: TRect;
  mTitleHeight, mTop, mIndex: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := UIFont;
  Canvas.Brush.Style := bsClear;
  mTitleHeight := Canvas.TextHeight('Wg');
  mArea := TitleArea(ClientWidth);
  Canvas.Font.Color := ToColor(Colors.Muted);
  DrawText(Canvas.Handle, PChar(FTitle), -1, mArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  mArea := BodyArea(TSize.Create(ClientWidth, ClientHeight));
  // MeasureText setzt die Schrift neu: vor der Farbe messen.
  if Length(FLinks) > 0 then
  begin
    mArea.Bottom := mArea.Top + MeasureText(mArea.Width).Height;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(Colors.Text);
  DrawText(Canvas.Handle, PChar(FText), -1, mArea, TextFlags or DT_END_ELLIPSIS);
  // Links darunter, je eine Zeile, unterstrichen im Akzent.
  SetLength(FLinkRects, Length(FLinks));
  if Length(FLinks) > 0 then
  begin
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.Font.Style := [fsUnderline];
    mTop := mArea.Bottom + Scale(6);
    for mIndex := 0 to High(FLinks) do
    begin
      mLinkArea := Rect(Scale(cPadding), mTop, Min(ClientWidth - Scale(cPadding), Scale(cPadding) +
        Canvas.TextWidth(FLinks[mIndex])), mTop + mTitleHeight);
      DrawText(Canvas.Handle, PChar(FLinks[mIndex]), -1, mLinkArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or
        DT_END_ELLIPSIS);
      FLinkRects[mIndex] := mLinkArea;
      Inc(mTop, mTitleHeight + Scale(2));
    end;
    Canvas.Font.Style := [];
  end;
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
