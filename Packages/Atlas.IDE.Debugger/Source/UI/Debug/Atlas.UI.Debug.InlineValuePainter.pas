unit Atlas.UI.Debug.InlineValuePainter;

// Werte im Editor beim Debuggen (#508), Zeichnen (nur GDI und VCL-Schrift):
// Schrift und Farben der Werte hinter dem Zeilenende, je Hintergrund bzw.
// Editorschrift einmal bestimmt. Gedimmt in der Farbe der Inlay-Hinweise,
// seit dem letzten Halt geänderte Werte in der Warnfarbe. Zeichnet zwischen
// SaveDC und RestoreDC; die IDE-Seite (TAtlasIdeDebugInlineValues) sucht Zeile
// und Platz aus. Angeheftete Werte (#526) stehen gerahmt mit einem Kreuz zum
// Lösen. Nur im Hauptthread verwenden.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Debug.InlineValues,
  Atlas.UI.Foundation.EditorFont;

type
  /// <summary>Schrift und Farben der Werte; je Hintergrund bzw. Editorschrift einmal bestimmt.</summary>
  TAtlasInlineValuePainter = class
  private
    FFont: TAtlasEditorFont;
    FBack: COLORREF;
    FBackKnown: Boolean;
    FTextColor: COLORREF;
    FChangedColor: COLORREF;
    procedure EnsureColors(ABack: COLORREF);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Ensure(ABack: COLORREF; const AEditorFont: TFont);
    /// <summary>AItems ab AX in ARect zeichnen; Ergebnis: rechte Kante.</summary>
    function Draw(ADC: HDC; const ARect: TRect; AX: Integer; const AItems: TAtlasInlineValueItems): Integer;
    /// <summary>AText gedimmt ab AX in ARect zeichnen („Warum bin ich hier?“, #1878); Ergebnis: rechte Kante.
    /// </summary>
    function DrawText(ADC: HDC; const ARect: TRect; AX: Integer; const AText: string): Integer;
    /// <summary>Angeheftetes Feld (#526): „Ausdruck = Wert ✕“ ab AX gerahmt, geänderte Werte in der Warnfarbe;
    /// AClose ist die Klickfläche des Kreuzes. Ergebnis: rechte Kante.</summary>
    function DrawPin(ADC: HDC; const ARect: TRect; AX: Integer; const AItem: TAtlasInlineValueItem;
      out AClose: TRect): Integer;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

{ TAtlasInlineValuePainter }

constructor TAtlasInlineValuePainter.Create;
begin
  inherited Create;
  FFont := TAtlasEditorFont.Create([fsItalic]);
end;

destructor TAtlasInlineValuePainter.Destroy;
begin
  FreeAndNil(FFont);
  inherited Destroy;
end;

procedure TAtlasInlineValuePainter.EnsureColors(ABack: COLORREF);
var
  mColors: TAtlasHintColors;
begin
  if FBackKnown and (FBack = ABack) then
  begin
    Exit;
  end;
  mColors := TAtlasColors.InlayHint(TAtlasColor(ABack));
  FTextColor := COLORREF(ColorToRGB(TColor(mColors.Text)));
  FChangedColor := COLORREF(ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ABack)).Warn)));
  FBack := ABack;
  FBackKnown := True;
end;

procedure TAtlasInlineValuePainter.Ensure(ABack: COLORREF; const AEditorFont: TFont);
begin
  EnsureColors(ABack);
  FFont.Follow(AEditorFont);
end;

function TAtlasInlineValuePainter.Draw(ADC: HDC; const ARect: TRect; AX: Integer;
  const AItems: TAtlasInlineValueItems): Integer;
var
  mSaved, mIndex, mTop: Integer;
  mSize: TSize;
  mPart: string;
begin
  Result := AX;
  mSaved := SaveDC(ADC);
  try
    SelectObject(ADC, FFont.Font.Handle);
    SetBkMode(ADC, TRANSPARENT);
    GetTextExtentPoint32W(ADC, 'Xg', 2, mSize);
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mSize.cy) div 2);
    for mIndex := 0 to High(AItems) do
    begin
      mPart := AItems[mIndex].Caption;
      if mIndex < High(AItems) then
      begin
        mPart := mPart + ', ';
      end;
      if AItems[mIndex].Changed then
      begin
        SetTextColor(ADC, FChangedColor);
      end
      else
      begin
        SetTextColor(ADC, FTextColor);
      end;
      TextOutW(ADC, Result, mTop, PChar(mPart), Length(mPart));
      GetTextExtentPoint32W(ADC, PChar(mPart), Length(mPart), mSize);
      Inc(Result, mSize.cx);
    end;
  finally
    RestoreDC(ADC, mSaved);
  end;
end;

function TAtlasInlineValuePainter.DrawText(ADC: HDC; const ARect: TRect; AX: Integer; const AText: string): Integer;
var
  mSaved, mTop: Integer;
  mSize: TSize;
begin
  Result := AX;
  if AText = '' then
  begin
    Exit;
  end;
  mSaved := SaveDC(ADC);
  try
    SelectObject(ADC, FFont.Handle);
    SetBkMode(ADC, TRANSPARENT);
    SetTextColor(ADC, FTextColor);
    GetTextExtentPoint32W(ADC, PChar(AText), Length(AText), mSize);
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mSize.cy) div 2);
    TextOutW(ADC, AX, mTop, PChar(AText), Length(AText));
    Inc(Result, mSize.cx);
  finally
    RestoreDC(ADC, mSaved);
  end;
end;

function TAtlasInlineValuePainter.DrawPin(ADC: HDC; const ARect: TRect; AX: Integer;
  const AItem: TAtlasInlineValueItem; out AClose: TRect): Integer;
const
  cPad = 4;
  cClose = ' ✕';
var
  mSaved, mTop, mRight: Integer;
  mSize, mCloseSize: TSize;
  mCaption: string;
  mPen: HPEN;
begin
  mCaption := AItem.Caption;
  mSaved := SaveDC(ADC);
  try
    SelectObject(ADC, FFont.Handle);
    SetBkMode(ADC, TRANSPARENT);
    GetTextExtentPoint32W(ADC, PChar(mCaption), Length(mCaption), mSize);
    GetTextExtentPoint32W(ADC, cClose, Length(cClose), mCloseSize);
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mSize.cy) div 2);
    mRight := AX + cPad + mSize.cx + mCloseSize.cx + cPad;
    // Rahmen in der Farbe des Texts, innen durchsichtig.
    mPen := CreatePen(PS_SOLID, 1, FTextColor);
    try
      SelectObject(ADC, mPen);
      SelectObject(ADC, GetStockObject(NULL_BRUSH));
      RoundRect(ADC, AX, ARect.Top + 1, mRight, ARect.Bottom - 1, 4, 4);
    finally
      SelectObject(ADC, GetStockObject(BLACK_PEN));
      DeleteObject(mPen);
    end;
    if AItem.Changed then
    begin
      SetTextColor(ADC, FChangedColor);
    end
    else
    begin
      SetTextColor(ADC, FTextColor);
    end;
    TextOutW(ADC, AX + cPad, mTop, PChar(mCaption), Length(mCaption));
    SetTextColor(ADC, FTextColor);
    TextOutW(ADC, AX + cPad + mSize.cx, mTop, cClose, Length(cClose));
    AClose := TRect.Create(AX + cPad + mSize.cx, ARect.Top, mRight, ARect.Bottom);
    Result := mRight;
  finally
    RestoreDC(ADC, mSaved);
  end;
end;

end.
