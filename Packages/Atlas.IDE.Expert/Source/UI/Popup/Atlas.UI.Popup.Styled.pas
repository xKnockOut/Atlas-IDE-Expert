unit Atlas.UI.Popup.Styled;

// Eingefärbter Code-Text für Detailpanel und Parameter-Hint (#411, #436):
// Schlüsselwörter halbfett in Schlüsselwortfarbe, Strings und Kommentare in
// eigener Farbe; optional ein aktiver Bereich (aktiver Parameter) halbfett in
// Akzentfarbe auf einer abgerundeten Akzentfläche; Standardwerte von Parametern
// (" = 1", #441) gedämpft. Messen und Zeichnen gehen
// über dieselben Stücke, damit Umbruch und Zeichnung übereinstimmen.
// P-09: Stücke ohne Array-Verkettung und ohne Sortieren je Token; der Umbruch
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
    procedure ApplyFont(ACanvas: TCanvas; const APiece: TPiece; ADimmed: Boolean);
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
    /// <summary>Zeichnet Text[AFrom..ATill) ab AX in der Zeile ARow; AX steht danach hinter dem Text.</summary>
    procedure Draw(ACanvas: TCanvas; const AColors: TAtlasColors; AFrom, ATill: Integer; var AX: Integer;
      const ARow: TRect; ADimmed: Boolean; ARadius: Integer);
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

function TAtlasStyledText.Pieces(AFrom, ATill: Integer): TArray<TPiece>;
var
  Token: TAtlasToken;
  Cuts: TArray<Integer>;
  CutCount, Count: Integer;
  Piece: TPiece;
  Index, From, Till, Value, Position: Integer;
  Range: TPoint;

  procedure AddCut(AValue: Integer);
  begin
    Cuts[CutCount] := AValue;
    Inc(CutCount);
  end;

begin
  Result := nil;
  Count := 0;
  // Höchstens Anfang, Ende, zwei aktive Grenzen und zwei je gedämpftem Bereich.
  Cuts := nil;
  SetLength(Cuts, 4 + 2 * Length(MutedRanges));
  for Token in Tokens do
  begin
    From := Max(AFrom, Token.Start);
    Till := Min(ATill, Token.Stop);
    if Till <= From then
      Continue;
    // Innerhalb des Tokens an den Grenzen des aktiven und der gedämpften Bereiche schneiden.
    CutCount := 0;
    AddCut(From);
    if (ActiveStart > From) and (ActiveStart < Till) then
      AddCut(ActiveStart);
    if (ActiveStop > From) and (ActiveStop < Till) then
      AddCut(ActiveStop);
    for Range in MutedRanges do
    begin
      if (Range.X > From) and (Range.X < Till) then
        AddCut(Range.X);
      if (Range.Y > From) and (Range.Y < Till) then
        AddCut(Range.Y);
    end;
    AddCut(Till);
    // Aufsteigend und ohne Doppelte: Einfügesortierung, die Liste ist winzig.
    for Index := 1 to CutCount - 1 do
    begin
      Value := Cuts[Index];
      Position := Index - 1;
      while (Position >= 0) and (Cuts[Position] > Value) do
      begin
        Cuts[Position + 1] := Cuts[Position];
        Dec(Position);
      end;
      Cuts[Position + 1] := Value;
    end;
    for Index := 0 to CutCount - 2 do
    begin
      if Cuts[Index + 1] = Cuts[Index] then
        Continue;
      Piece.Start := Cuts[Index];
      Piece.Stop := Cuts[Index + 1];
      Piece.Kind := Token.Kind;
      Piece.Active := (ActiveStart >= 0) and (Piece.Start >= ActiveStart) and (Piece.Stop <= ActiveStop);
      Piece.Muted := False;
      for Range in MutedRanges do
        if (Piece.Start >= Range.X) and (Piece.Stop <= Range.Y) then
          Piece.Muted := True;
      if Count = Length(Result) then
        SetLength(Result, 2 * Count + 8);
      Result[Count] := Piece;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

procedure TAtlasStyledText.ApplyFont(ACanvas: TCanvas; const APiece: TPiece; ADimmed: Boolean);
begin
  // Breite und Zeichnung gleich: Schlüsselwörter auch gedämpft halbfett.
  if APiece.Active or (not APiece.Muted and (APiece.Kind = TAtlasTokenKind.Keyword)) then
    ACanvas.Font.Style := [fsBold]
  else
    ACanvas.Font.Style := [];
end;

function TAtlasStyledText.Width(ACanvas: TCanvas; AFrom, ATill: Integer): Integer;
var
  Piece: TPiece;
begin
  Result := 0;
  for Piece in Pieces(AFrom, ATill) do
  begin
    ApplyFont(ACanvas, Piece, False);
    Inc(Result, ACanvas.TextWidth(Copy(Text, Piece.Start + 1, Piece.Stop - Piece.Start)));
  end;
  ACanvas.Font.Style := [];
end;

procedure TAtlasStyledText.Draw(ACanvas: TCanvas; const AColors: TAtlasColors; AFrom, ATill: Integer;
  var AX: Integer; const ARow: TRect; ADimmed: Boolean; ARadius: Integer);
const
  Flags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
var
  AllPieces: TArray<TPiece>;
  Piece: TPiece;
  Widths: TArray<Integer>;
  Index, X, FillStart, Pad: Integer;
  Part: TRect;
  Color: TAtlasColor;
  PieceText: string;
begin
  AllPieces := Pieces(AFrom, ATill);
  SetLength(Widths, Length(AllPieces));
  for Index := 0 to High(AllPieces) do
  begin
    ApplyFont(ACanvas, AllPieces[Index], ADimmed);
    Widths[Index] := ACanvas.TextWidth(Copy(Text, AllPieces[Index].Start + 1,
      AllPieces[Index].Stop - AllPieces[Index].Start));
  end;
  // 1. Akzentfläche unter dem aktiven Bereich (vor dem Text, damit Nachbarzeichen darüber liegen).
  if ActiveFill and not ADimmed then
  begin
    X := AX;
    FillStart := -1;
    Pad := Max(1, ARadius div 2);
    for Index := 0 to High(AllPieces) do
    begin
      if AllPieces[Index].Active and (FillStart < 0) then
        FillStart := X;
      Inc(X, Widths[Index]);
      if (FillStart >= 0) and ((Index = High(AllPieces)) or not AllPieces[Index + 1].Active) then
      begin
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := TColor(AColors.AccentSoft);
        ACanvas.Pen.Style := psClear;
        ACanvas.RoundRect(FillStart - Pad, ARow.Top + 1, Min(X + Pad, ARow.Right) + 1, ARow.Bottom, 2 * ARadius,
          2 * ARadius);
        ACanvas.Pen.Style := psSolid;
        FillStart := -1;
      end;
    end;
  end;
  // 2. Text.
  ACanvas.Brush.Style := bsClear;
  for Index := 0 to High(AllPieces) do
  begin
    Piece := AllPieces[Index];
    if AX >= ARow.Right then
      Break;
    if Piece.Active and not ADimmed then
      Color := AColors.Accent
    else if ADimmed or Piece.Muted then
      Color := AColors.Muted
    else
      case Piece.Kind of
        TAtlasTokenKind.Keyword: Color := AColors.Keyword;
        TAtlasTokenKind.StringLiteral: Color := AColors.StringLiteral;
        TAtlasTokenKind.Comment: Color := AColors.Comment;
      else
        Color := AColors.Text;
      end;
    ApplyFont(ACanvas, Piece, ADimmed);
    ACanvas.Font.Color := TColor(Color);
    PieceText := Copy(Text, Piece.Start + 1, Piece.Stop - Piece.Start);
    Part := Rect(AX, ARow.Top, ARow.Right, ARow.Bottom);
    DrawText(ACanvas.Handle, PChar(PieceText), -1, Part, Flags or DT_END_ELLIPSIS);
    Inc(AX, Widths[Index]);
  end;
  ACanvas.Font.Style := [];
  ACanvas.Brush.Style := bsSolid;
end;

function TAtlasStyledText.PrefixWidths(ACanvas: TCanvas): TArray<Integer>;
var
  Piece: TPiece;
  Partial: TArray<Integer>;
  PieceText: string;
  Index, Base, Fit, Done: Integer;
  Size: TSize;
begin
  Result := nil;
  SetLength(Result, Length(Text) + 1);
  Result[0] := 0;
  Done := 0;
  for Piece in Pieces(0, Length(Text)) do
  begin
    // Lücke ohne Token (kommt bei TAtlasSyntax nicht vor): Breite 0 wie bisher in Width.
    for Index := Done + 1 to Piece.Start do
      Result[Index] := Result[Done];
    Done := Piece.Stop;
    ApplyFont(ACanvas, Piece, False);
    PieceText := Copy(Text, Piece.Start + 1, Piece.Stop - Piece.Start);
    // TextWidth wählt die Schrift mit dem Stil des Stücks in den DC; dann Teilbreiten je Zeichen.
    Base := Result[Piece.Start];
    Result[Piece.Stop] := Base + ACanvas.TextWidth(PieceText);
    Partial := nil;
    SetLength(Partial, Length(PieceText));
    if (Length(PieceText) > 0) and GetTextExtentExPointW(ACanvas.Handle, PChar(PieceText), Length(PieceText),
      MaxInt, @Fit, @Partial[0], Size) then
      for Index := 0 to High(Partial) - 1 do
        Result[Piece.Start + Index + 1] := Base + Partial[Index];
  end;
  for Index := Done + 1 to Length(Text) do
    Result[Index] := Result[Done];
  ACanvas.Font.Style := [];
end;

function TAtlasStyledText.WrapAtSpaces(ACanvas: TCanvas; AWidth, AIndent: Integer): TArray<TPoint>;
begin
  // Umbruch hinter Leerzeichen; ein Wort, das allein nicht passt, steht allein (gekürzt).
  Result := TAtlasWrap.AtSpaces(Text, PrefixWidths(ACanvas), AWidth, AIndent);
end;

end.
