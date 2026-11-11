unit Atlas.UI.Popup.Styled;

// Eingefärbter Code-Text für Detailpanel und Parameter-Hint (#411, #436):
// Schlüsselwörter halbfett in Schlüsselwortfarbe, Strings und Kommentare in
// eigener Farbe; optional ein aktiver Bereich (aktiver Parameter) halbfett in
// Akzentfarbe auf einer abgerundeten Akzentfläche; Standardwerte von Parametern
// (" = 1", #441) gedämpft. Messen und Zeichnen gehen
// über dieselben Stücke, damit Umbruch und Zeichnung übereinstimmen.
// Schnell: Stücke ohne Array-Verkettung und ohne Sortieren je Token; der Umbruch
// misst den Text einmal (Präfixsummen) und rechnet dann nur noch Differenzen
// (TAtlasWrap).

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Syntax;

type
  /// <summary>Wohin gezeichnet wird: Leinwand, Farben und Eckradius der Akzentfläche.</summary>
  TAtlasStyledTarget = record
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Radius: Integer;
    class function Create(ACanvas: TCanvas; const AColors: TAtlasColors; ARadius: Integer): TAtlasStyledTarget;
      static;
  end;

  TAtlasStyledText = record
  private type
    TPiece = record
      Start: Integer;
      Stop: Integer;
      Kind: TAtlasTokenKind;
      Active: Boolean;
      Muted: Boolean;
    end;
  private
    function Pieces(AFrom, ATill: Integer): TArray<TPiece>;
    /// <summary>Schnitte in [AFrom, ATill] an den Grenzen des aktiven und der gedämpften Bereiche, aufsteigend;
    /// liefert ihre Zahl.</summary>
    function CutsWithin(AFrom, ATill: Integer; var ACuts: TArray<Integer>): Integer;
    function PieceOf(AStart, AStop: Integer; AKind: TAtlasTokenKind): TPiece;
    function PieceText(const APiece: TPiece): string;
    function PieceWidths(ACanvas: TCanvas; const APieces: TArray<TPiece>): TArray<Integer>;
    procedure ApplyFont(ACanvas: TCanvas; const APiece: TPiece);
  public
    Text: string;
    Tokens: TAtlasTokens;
    /// <summary>Aktiver Bereich, 0-basiert, Stop exklusiv; -1 ohne.</summary>
    ActiveStart: Integer;
    ActiveStop: Integer;
    /// <summary>Aktiven Bereich auf Akzentfläche (sonst nur halbfett).</summary>
    ActiveFill: Boolean;
    /// <summary>Gedämpfte Bereiche (Standardwerte), X = Start, Y = Stop.</summary>
    MutedRanges: TArray<TPoint>;
    class function Create(const AText: string): TAtlasStyledText; static;
    /// <summary>Breite von Text[AFrom..ATill) in der Schrift von ACanvas.</summary>
    function Width(ACanvas: TCanvas; AFrom, ATill: Integer): Integer;
    /// <summary>Zeichnet Text[AFrom..ATill) ab AX in der Zeile ARow; AX steht danach hinter dem Text.
    /// ARange: X = AFrom, Y = ATill (wie die Zeilen von WrapAtSpaces).</summary>
    procedure Draw(const ATarget: TAtlasStyledTarget; const ARange: TPoint; var AX: Integer; const ARow: TRect;
      ADimmed: Boolean);
    /// <summary>Breiten aller Präfixe: Ergebnis[i] = Breite von Text[0..i), Länge Length(Text) + 1.</summary>
    function PrefixWidths(ACanvas: TCanvas): TArray<Integer>;
    /// <summary>Zeilen (Bereiche) bei Umbruch an Leerzeichen; Folgezeilen um AIndent schmaler.</summary>
    function WrapAtSpaces(ACanvas: TCanvas; AWidth, AIndent: Integer): TArray<TPoint>;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.Core.Style.Wrap;

/// <summary>ACuts[0..ACount) aufsteigend: Einfügesortierung, die Liste ist winzig.</summary>
procedure SortCuts(var ACuts: TArray<Integer>; ACount: Integer);
var
  mIndex, mValue, mPosition: Integer;
begin
  for mIndex := 1 to ACount - 1 do
  begin
    mValue := ACuts[mIndex];
    mPosition := mIndex - 1;
    while (mPosition >= 0) and (ACuts[mPosition] > mValue) do
    begin
      ACuts[mPosition + 1] := ACuts[mPosition];
      Dec(mPosition);
    end;
    ACuts[mPosition + 1] := mValue;
  end;
end;

/// <summary>Farbe eines Stücks: aktiv in Akzent, gedämpft, sonst nach der Art des Tokens.</summary>
function PieceColor(const AColors: TAtlasColors; AKind: TAtlasTokenKind; AActive, AMuted: Boolean): TAtlasColor;
begin
  if AActive then
  begin
    Exit(AColors.Accent);
  end;
  if AMuted then
  begin
    Exit(AColors.Muted);
  end;
  case AKind of
    TAtlasTokenKind.Keyword: Result := AColors.Keyword;
    TAtlasTokenKind.StringLiteral: Result := AColors.StringLiteral;
    TAtlasTokenKind.Comment: Result := AColors.Comment;
  else
    Result := AColors.Text;
  end;
end;

{ TAtlasStyledTarget }

class function TAtlasStyledTarget.Create(ACanvas: TCanvas; const AColors: TAtlasColors;
  ARadius: Integer): TAtlasStyledTarget;
begin
  Result.Canvas := ACanvas;
  Result.Colors := AColors;
  Result.Radius := ARadius;
end;

{ TAtlasStyledText }

class function TAtlasStyledText.Create(const AText: string): TAtlasStyledText;
begin
  Result.Text := AText;
  Result.Tokens := TAtlasSyntax.Tokens(AText);
  Result.ActiveStart := -1;
  Result.ActiveStop := -1;
  Result.ActiveFill := True;
  Result.MutedRanges := TAtlasSyntax.DefaultRanges(AText);
end;

function TAtlasStyledText.CutsWithin(AFrom, ATill: Integer; var ACuts: TArray<Integer>): Integer;
var
  mCount: Integer;
  mRange: TPoint;

  procedure AddInside(AValue: Integer);
  begin
    if (AValue > AFrom) and (AValue < ATill) then
    begin
      ACuts[mCount] := AValue;
      Inc(mCount);
    end;
  end;

begin
  ACuts[0] := AFrom;
  mCount := 1;
  AddInside(ActiveStart);
  AddInside(ActiveStop);
  for mRange in MutedRanges do
  begin
    AddInside(mRange.X);
    AddInside(mRange.Y);
  end;
  ACuts[mCount] := ATill;
  Inc(mCount);
  SortCuts(ACuts, mCount);
  Result := mCount;
end;

function TAtlasStyledText.PieceOf(AStart, AStop: Integer; AKind: TAtlasTokenKind): TPiece;
var
  mRange: TPoint;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Kind := AKind;
  Result.Active := (ActiveStart >= 0) and (AStart >= ActiveStart) and (AStop <= ActiveStop);
  Result.Muted := False;
  for mRange in MutedRanges do
  begin
    if (AStart >= mRange.X) and (AStop <= mRange.Y) then
    begin
      Result.Muted := True;
    end;
  end;
end;

function TAtlasStyledText.PieceText(const APiece: TPiece): string;
begin
  Result := Copy(Text, APiece.Start + 1, APiece.Stop - APiece.Start);
end;

function TAtlasStyledText.Pieces(AFrom, ATill: Integer): TArray<TPiece>;
var
  mToken: TAtlasToken;
  mCuts: TArray<Integer>;
  mCutCount, mCount, mIndex: Integer;
begin
  Result := nil;
  mCount := 0;
  // Höchstens Anfang, Ende, zwei aktive Grenzen und zwei je gedämpftem Bereich.
  mCuts := nil;
  SetLength(mCuts, 4 + 2 * Length(MutedRanges));
  for mToken in Tokens do
  begin
    if Min(ATill, mToken.Stop) <= Max(AFrom, mToken.Start) then
    begin
      Continue;
    end;
    // Innerhalb des Tokens an den Grenzen des aktiven und der gedämpften Bereiche schneiden.
    mCutCount := CutsWithin(Max(AFrom, mToken.Start), Min(ATill, mToken.Stop), mCuts);
    for mIndex := 0 to mCutCount - 2 do
    begin
      if mCuts[mIndex + 1] = mCuts[mIndex] then
      begin
        Continue;
      end;
      if mCount = Length(Result) then
      begin
        SetLength(Result, 2 * mCount + 8);
      end;
      Result[mCount] := PieceOf(mCuts[mIndex], mCuts[mIndex + 1], mToken.Kind);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TAtlasStyledText.PieceWidths(ACanvas: TCanvas; const APieces: TArray<TPiece>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APieces));
  for mIndex := 0 to High(APieces) do
  begin
    ApplyFont(ACanvas, APieces[mIndex]);
    Result[mIndex] := ACanvas.TextWidth(PieceText(APieces[mIndex]));
  end;
end;

procedure TAtlasStyledText.ApplyFont(ACanvas: TCanvas; const APiece: TPiece);
begin
  // Breite und Zeichnung gleich: Schlüsselwörter auch gedämpft halbfett.
  if APiece.Active or (not APiece.Muted and (APiece.Kind = TAtlasTokenKind.Keyword)) then
  begin
    ACanvas.Font.Style := [fsBold];
  end
  else
  begin
    ACanvas.Font.Style := [];
  end;
end;

function TAtlasStyledText.Width(ACanvas: TCanvas; AFrom, ATill: Integer): Integer;
var
  mPiece: TPiece;
begin
  Result := 0;
  for mPiece in Pieces(AFrom, ATill) do
  begin
    ApplyFont(ACanvas, mPiece);
    Inc(Result, ACanvas.TextWidth(Copy(Text, mPiece.Start + 1, mPiece.Stop - mPiece.Start)));
  end;
  ACanvas.Font.Style := [];
end;

/// <summary>Akzentfläche unter jedem zusammenhängenden aktiven Lauf ab AX.</summary>
procedure DrawActiveFill(const ATarget: TAtlasStyledTarget; const AActive: TArray<Boolean>;
  const AWidths: TArray<Integer>; AX: Integer; const ARow: TRect);
var
  mIndex, mX, mFillStart, mPad: Integer;
  mCanvas: TCanvas;
begin
  mCanvas := ATarget.Canvas;
  mX := AX;
  mFillStart := -1;
  mPad := Max(1, ATarget.Radius div 2);
  for mIndex := 0 to High(AActive) do
  begin
    if AActive[mIndex] and (mFillStart < 0) then
    begin
      mFillStart := mX;
    end;
    Inc(mX, AWidths[mIndex]);
    if (mFillStart >= 0) and ((mIndex = High(AActive)) or not AActive[mIndex + 1]) then
    begin
      mCanvas.Brush.Style := bsSolid;
      mCanvas.Brush.Color := TColor(ATarget.Colors.AccentSoft);
      mCanvas.Pen.Style := psClear;
      mCanvas.RoundRect(mFillStart - mPad, ARow.Top + 1, Min(mX + mPad, ARow.Right) + 1, ARow.Bottom,
        2 * ATarget.Radius, 2 * ATarget.Radius);
      mCanvas.Pen.Style := psSolid;
      mFillStart := -1;
    end;
  end;
end;

procedure TAtlasStyledText.Draw(const ATarget: TAtlasStyledTarget; const ARange: TPoint; var AX: Integer;
  const ARow: TRect; ADimmed: Boolean);
const
  cFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  mPieces: TArray<TPiece>;
  mWidths: TArray<Integer>;
  mActive: TArray<Boolean>;
  mIndex: Integer;
  mPart: TRect;
  mText: string;
  mCanvas: TCanvas;
begin
  mCanvas := ATarget.Canvas;
  mPieces := Pieces(ARange.X, ARange.Y);
  mWidths := PieceWidths(mCanvas, mPieces);
  // 1. Akzentfläche unter dem aktiven Bereich (vor dem Text, damit Nachbarzeichen darüber liegen).
  if ActiveFill and not ADimmed then
  begin
    SetLength(mActive, Length(mPieces));
    for mIndex := 0 to High(mPieces) do
    begin
      mActive[mIndex] := mPieces[mIndex].Active;
    end;
    DrawActiveFill(ATarget, mActive, mWidths, AX, ARow);
  end;
  // 2. Text.
  mCanvas.Brush.Style := bsClear;
  for mIndex := 0 to High(mPieces) do
  begin
    if AX >= ARow.Right then
    begin
      Break;
    end;
    ApplyFont(mCanvas, mPieces[mIndex]);
    mCanvas.Font.Color := TColor(PieceColor(ATarget.Colors, mPieces[mIndex].Kind,
      mPieces[mIndex].Active and not ADimmed, ADimmed or mPieces[mIndex].Muted));
    mText := PieceText(mPieces[mIndex]);
    mPart := Rect(AX, ARow.Top, ARow.Right, ARow.Bottom);
    DrawText(mCanvas.Handle, PChar(mText), -1, mPart, cFlags);
    Inc(AX, mWidths[mIndex]);
  end;
  mCanvas.Font.Style := [];
  mCanvas.Brush.Style := bsSolid;
end;

function TAtlasStyledText.PrefixWidths(ACanvas: TCanvas): TArray<Integer>;
var
  mPiece: TPiece;
  mPartial: TArray<Integer>;
  mPieceText: string;
  mIndex, mBase, mFit, mDone: Integer;
  mSize: TSize;
begin
  Result := nil;
  SetLength(Result, Length(Text) + 1);
  Result[0] := 0;
  mDone := 0;
  for mPiece in Pieces(0, Length(Text)) do
  begin
    // Lücke ohne Token (kommt bei TAtlasSyntax nicht vor): Breite 0 wie bisher in Width.
    for mIndex := mDone + 1 to mPiece.Start do
    begin
      Result[mIndex] := Result[mDone];
    end;
    mDone := mPiece.Stop;
    ApplyFont(ACanvas, mPiece);
    mPieceText := Copy(Text, mPiece.Start + 1, mPiece.Stop - mPiece.Start);
    // TextWidth wählt die Schrift mit dem Stil des Stücks in den DC; dann Teilbreiten je Zeichen.
    mBase := Result[mPiece.Start];
    Result[mPiece.Stop] := mBase + ACanvas.TextWidth(mPieceText);
    mPartial := nil;
    SetLength(mPartial, Length(mPieceText));
    if (Length(mPieceText) > 0) and GetTextExtentExPointW(ACanvas.Handle, PChar(mPieceText), Length(mPieceText),
      MaxInt, @mFit, @mPartial[0], mSize) then
    begin
      for mIndex := 0 to High(mPartial) - 1 do
      begin
        Result[mPiece.Start + mIndex + 1] := mBase + mPartial[mIndex];
      end;
    end;
  end;
  for mIndex := mDone + 1 to Length(Text) do
  begin
    Result[mIndex] := Result[mDone];
  end;
  ACanvas.Font.Style := [];
end;

function TAtlasStyledText.WrapAtSpaces(ACanvas: TCanvas; AWidth, AIndent: Integer): TArray<TPoint>;
begin
  // Umbruch hinter Leerzeichen; ein Wort, das allein nicht passt, steht allein (gekürzt).
  Result := TAtlasWrap.AtSpaces(Text, PrefixWidths(ACanvas), AWidth, AIndent);
end;

end.
