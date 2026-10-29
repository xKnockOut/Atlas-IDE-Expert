unit Atlas.UI.Notes.Tip;

// Tooltip einer persönlichen Notiz (#545) beim Überfahren ihres Symbols in
// der Rinne: oben gedämpft „Notiz vom 15.10.2026“, darunter der Text, auch
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
  TAtlasNoteTip = class(TAtlasPopupWindow)
  public const
    /// <summary>Höchstbreite des Textes in logischen Pixeln (96 dpi).</summary>
    MaxWidth = 420;
    Padding = 9;
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
    function LinkAt(X, Y: Integer): Integer;
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

{ TAtlasNoteTip }

constructor TAtlasNoteTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Notes;
end;

function TAtlasNoteTip.TextFlags: Cardinal;
begin
  Result := DT_LEFT or DT_TOP or DT_WORDBREAK or DT_NOPREFIX or DT_EXPANDTABS;
end;

function TAtlasNoteTip.MeasureText(AWidth: Integer): TRect;
var
  Shown: string;
begin
  Shown := FText;
  if Shown = '' then
    Shown := ' ';
  Result := Rect(0, 0, AWidth, 0);
  Canvas.Font := UIFont;
  DrawText(Canvas.Handle, PChar(Shown), -1, Result, TextFlags or DT_CALCRECT);
end;

function TAtlasNoteTip.TitleArea(AClientWidth: Integer): TRect;
begin
  Canvas.Font := UIFont;
  Result := Rect(Scale(Padding), Scale(Padding) - Scale(2), AClientWidth - Scale(Padding),
    Scale(Padding) - Scale(2) + Canvas.TextHeight('Wg'));
end;

function TAtlasNoteTip.BodyArea(const ASize: TSize): TRect;
begin
  Result := Rect(Scale(Padding), TitleArea(ASize.cx).Bottom + Scale(4), ASize.cx - Scale(Padding),
    ASize.cy - Scale(Padding));
end;

function TAtlasNoteTip.Measure(const ATitle, AText: string): TSize;
begin
  Result := Measure(ATitle, AText, nil);
end;

function TAtlasNoteTip.Measure(const ATitle, AText: string; const ALinks: TArray<string>): TSize;
var
  Body: TRect;
  TitleWidth, mWidth, LinkWidth, LineHeight: Integer;
  Link: string;
begin
  FTitle := ATitle;
  FLinks := ALinks;
  FLinkRects := nil;
  // Zeilenumbrüche der Notiz als Windows-Umbrüche, damit DrawText sie einhält.
  FText := AText.Replace(#13#10, #10).Replace(#10, #13#10);
  Canvas.Font := UIFont;
  TitleWidth := Canvas.TextWidth(FTitle);
  Body := MeasureText(Scale(MaxWidth));
  FBodyHeight := Body.Height;
  mWidth := Max(TitleWidth, Body.Width);
  LineHeight := Canvas.TextHeight('Wg');
  for Link in FLinks do
  begin
    LinkWidth := Canvas.TextWidth(Link);
    if LinkWidth > mWidth then
      mWidth := LinkWidth;
  end;
  Result.cx := Min(mWidth, Scale(MaxWidth)) + 2 * Scale(Padding);
  // Wie TitleArea und BodyArea: Überschrift ab Padding - 2, Abstand 4, Text, Padding unten.
  Result.cy := TitleArea(Result.cx).Bottom + Scale(4) + Body.Height + Scale(Padding);
  if Length(FLinks) > 0 then
    Inc(Result.cy, Scale(6) + Length(FLinks) * (LineHeight + Scale(2)));
end;

procedure TAtlasNoteTip.ShowNote(const ATitle, AText: string; const APoint: TPoint);
begin
  ShowNote(ATitle, AText, nil, APoint);
end;

procedure TAtlasNoteTip.ShowNote(const ATitle, AText: string; const ALinks: TArray<string>; const APoint: TPoint);
var
  Area, Bounds: TRect;
  Size: TSize;
begin
  Size := Measure(ATitle, AText, ALinks);
  Area := WorkAreaAt(APoint);
  Size.cx := Min(Size.cx, Area.Width);
  Size.cy := Min(Size.cy, Area.Height);
  Bounds := TRect.Create(APoint, Size.cx, Size.cy);
  if Bounds.Right > Area.Right then
    Bounds.SetLocation(Max(Area.Left, Area.Right - Size.cx), Bounds.Top);
  if Bounds.Bottom > Area.Bottom then
    Bounds.SetLocation(Bounds.Left, Max(Area.Top, Area.Bottom - Size.cy));
  SetAccessible(UiaToolTipControlType, ATitle);
  ShowAt(Bounds);
  Invalidate;
  if Length(ALinks) > 0 then
    Announce(ATitle + '. ' + AText + '. ' + string.Join(', ', ALinks))
  else
    Announce(ATitle + '. ' + AText);
end;

function TAtlasNoteTip.LinkAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FLinkRects) do
    if PtInRect(FLinkRects[Index], Point(X, Y)) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasNoteTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Index := LinkAt(X, Y);
  if (Button = mbLeft) and (Index >= 0) and Assigned(FOnLink) then
    TAtlasGuard.Run(GuardFeature,
      procedure
      begin
        FOnLink(Index);
      end);
end;

procedure TAtlasNoteTip.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if LinkAt(X, Y) >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

procedure TAtlasNoteTip.Paint;
var
  Area, LinkArea: TRect;
  TitleHeight, mTop, Index: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := UIFont;
  Canvas.Brush.Style := bsClear;
  TitleHeight := Canvas.TextHeight('Wg');
  Area := TitleArea(ClientWidth);
  Canvas.Font.Color := ToColor(Colors.Muted);
  DrawText(Canvas.Handle, PChar(FTitle), -1, Area, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Area := BodyArea(TSize.Create(ClientWidth, ClientHeight));
  // MeasureText setzt die Schrift neu: vor der Farbe messen.
  if Length(FLinks) > 0 then
    Area.Bottom := Area.Top + MeasureText(Area.Width).Height;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(Colors.Text);
  DrawText(Canvas.Handle, PChar(FText), -1, Area, TextFlags or DT_END_ELLIPSIS);
  // Links darunter, je eine Zeile, unterstrichen im Akzent.
  SetLength(FLinkRects, Length(FLinks));
  if Length(FLinks) > 0 then
  begin
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.Font.Style := [fsUnderline];
    mTop := Area.Bottom + Scale(6);
    for Index := 0 to High(FLinks) do
    begin
      LinkArea := Rect(Scale(Padding), mTop, Min(ClientWidth - Scale(Padding), Scale(Padding) +
        Canvas.TextWidth(FLinks[Index])), mTop + TitleHeight);
      DrawText(Canvas.Handle, PChar(FLinks[Index]), -1, LinkArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or
        DT_END_ELLIPSIS);
      FLinkRects[Index] := LinkArea;
      Inc(mTop, TitleHeight + Scale(2));
    end;
    Canvas.Font.Style := [];
  end;
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
