unit Atlas.Common.Editing.Colors;

// Farbwerte im Quelltext (#26): TColor-Hex ($00BBGGRR, Blau zuerst),
// RGB(r, g, b), benannte Farben (clRed) und Systemfarben (clBtnFace).
// Find liefert Farbe und Ausgangsformat je Fundstelle, Presentations die
// Schreibweisen für eine neue Farbe, die erste im Ausgangsformat.
// Systemfarben hängen vom Rechner ab; ihren Wert liefert ein Provider
// (Windows: GetSysColor), sonst gelten die Standardwerte von Windows 10.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  {$SCOPEDENUMS ON}
  TColorFormat = (Hex, Rgb, Named, SystemColor);
  {$SCOPEDENUMS OFF}

  TRgbColor = record
    R, G, B: Byte;
    constructor Create(AR, AG, AB: Byte);
    /// <summary>Aus einem TColor-Wert ($00BBGGRR).</summary>
    class function FromTColor(AValue: Cardinal): TRgbColor; static;
    function ToTColor: Cardinal;
    class operator Equal(const A, B: TRgbColor): Boolean;
    class operator NotEqual(const A, B: TRgbColor): Boolean;
  end;

  /// <summary>Wert einer Systemfarbe über den Index von GetSysColor; False = unbekannt.</summary>
  TSystemColorProvider = reference to function(AIndex: Integer; out AColor: TRgbColor): Boolean;

  TColorMatch = record
    Range: TTextRange;
    Color: TRgbColor;
    Format: TColorFormat;
    /// <summary>Quelltext der Fundstelle.</summary>
    Text: string;
  end;

  TColorPresentation = record
    /// <summary>Text, der die Fundstelle ersetzt.</summary>
    Text: string;
    Format: TColorFormat;
  end;

  TSourceColors = class
  public
    /// <summary>Alle Farbwerte in AText.</summary>
    class function Find(const AText: string; const ASystemColors: TSystemColorProvider = nil): TArray<TColorMatch>; static;
    /// <summary>Schreibweisen für AColor; die erste entspricht AFormat (Systemfarben werden zu Hex).</summary>
    class function Presentations(const AColor: TRgbColor; AFormat: TColorFormat): TArray<TColorPresentation>; static;
    /// <summary>TColor-Hex wie $00FF8000 (Großbuchstaben, 8 Stellen).</summary>
    class function HexText(const AColor: TRgbColor): string; static;
    /// <summary>Benannte Farbe mit genau diesem Wert, sonst ''.</summary>
    class function NameOf(const AColor: TRgbColor): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

type
  TNamedColor = record
    Name: string;
    /// <summary>RGB als $RRGGBB.</summary>
    Value: Cardinal;
  end;

  TSystemColor = record
    Name: string;
    Index: Integer;
    /// <summary>Standardwert unter Windows 10, $RRGGBB.</summary>
    DefaultValue: Cardinal;
  end;

const
  NamedColors: array[0..21] of TNamedColor = (
    (Name: 'clBlack'; Value: $000000), (Name: 'clMaroon'; Value: $800000),
    (Name: 'clGreen'; Value: $008000), (Name: 'clOlive'; Value: $808000),
    (Name: 'clNavy'; Value: $000080), (Name: 'clPurple'; Value: $800080),
    (Name: 'clTeal'; Value: $008080), (Name: 'clGray'; Value: $808080),
    (Name: 'clSilver'; Value: $C0C0C0), (Name: 'clRed'; Value: $FF0000),
    (Name: 'clLime'; Value: $00FF00), (Name: 'clYellow'; Value: $FFFF00),
    (Name: 'clBlue'; Value: $0000FF), (Name: 'clFuchsia'; Value: $FF00FF),
    (Name: 'clAqua'; Value: $00FFFF), (Name: 'clWhite'; Value: $FFFFFF),
    (Name: 'clMoneyGreen'; Value: $C0DCC0), (Name: 'clSkyBlue'; Value: $A6CAF0),
    (Name: 'clCream'; Value: $FFFBF0), (Name: 'clMedGray'; Value: $A0A0A4),
    // Gleiche Werte wie clGray/clSilver; NameOf liefert den ersten Treffer.
    (Name: 'clDkGray'; Value: $808080), (Name: 'clLtGray'; Value: $C0C0C0));

  SystemColors: array[0..29] of TSystemColor = (
    (Name: 'clScrollBar'; Index: 0; DefaultValue: $C8C8C8),
    (Name: 'clBackground'; Index: 1; DefaultValue: $000000),
    (Name: 'clActiveCaption'; Index: 2; DefaultValue: $99B4D1),
    (Name: 'clInactiveCaption'; Index: 3; DefaultValue: $BFCDDB),
    (Name: 'clMenu'; Index: 4; DefaultValue: $F0F0F0),
    (Name: 'clWindow'; Index: 5; DefaultValue: $FFFFFF),
    (Name: 'clWindowFrame'; Index: 6; DefaultValue: $646464),
    (Name: 'clMenuText'; Index: 7; DefaultValue: $000000),
    (Name: 'clWindowText'; Index: 8; DefaultValue: $000000),
    (Name: 'clCaptionText'; Index: 9; DefaultValue: $000000),
    (Name: 'clActiveBorder'; Index: 10; DefaultValue: $B4B4B4),
    (Name: 'clInactiveBorder'; Index: 11; DefaultValue: $F4F7FC),
    (Name: 'clAppWorkSpace'; Index: 12; DefaultValue: $ABABAB),
    (Name: 'clHighlight'; Index: 13; DefaultValue: $0078D7),
    (Name: 'clHighlightText'; Index: 14; DefaultValue: $FFFFFF),
    (Name: 'clBtnFace'; Index: 15; DefaultValue: $F0F0F0),
    (Name: 'clBtnShadow'; Index: 16; DefaultValue: $A0A0A0),
    (Name: 'clGrayText'; Index: 17; DefaultValue: $6D6D6D),
    (Name: 'clBtnText'; Index: 18; DefaultValue: $000000),
    (Name: 'clInactiveCaptionText'; Index: 19; DefaultValue: $000000),
    (Name: 'clBtnHighlight'; Index: 20; DefaultValue: $FFFFFF),
    (Name: 'cl3DDkShadow'; Index: 21; DefaultValue: $696969),
    (Name: 'cl3DLight'; Index: 22; DefaultValue: $E3E3E3),
    (Name: 'clInfoText'; Index: 23; DefaultValue: $000000),
    (Name: 'clInfoBk'; Index: 24; DefaultValue: $FFFFE1),
    (Name: 'clHotLight'; Index: 26; DefaultValue: $0066CC),
    (Name: 'clGradientActiveCaption'; Index: 27; DefaultValue: $B9D1EA),
    (Name: 'clGradientInactiveCaption'; Index: 28; DefaultValue: $D7E4F2),
    (Name: 'clMenuHighlight'; Index: 29; DefaultValue: $3399FF),
    (Name: 'clMenuBar'; Index: 30; DefaultValue: $F0F0F0));

function FromRgbValue(AValue: Cardinal): TRgbColor;
begin
  Result := TRgbColor.Create((AValue shr 16) and $FF, (AValue shr 8) and $FF, AValue and $FF);
end;

{ TRgbColor }

constructor TRgbColor.Create(AR, AG, AB: Byte);
begin
  R := AR;
  G := AG;
  B := AB;
end;

class function TRgbColor.FromTColor(AValue: Cardinal): TRgbColor;
begin
  Result := TRgbColor.Create(AValue and $FF, (AValue shr 8) and $FF, (AValue shr 16) and $FF);
end;

function TRgbColor.ToTColor: Cardinal;
begin
  Result := R or (Cardinal(G) shl 8) or (Cardinal(B) shl 16);
end;

class operator TRgbColor.Equal(const A, B: TRgbColor): Boolean;
begin
  Result := (A.R = B.R) and (A.G = B.G) and (A.B = B.B);
end;

class operator TRgbColor.NotEqual(const A, B: TRgbColor): Boolean;
begin
  Result := not (A = B);
end;

{ Suche }

function SignificantIndex(const ATokens: TArray<TPascalToken>; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(Result);
end;

function TryByte(const AToken: TPascalToken; out AValue: Byte): Boolean;
var
  Value: Integer;
begin
  Result := (AToken.Kind = TPascalTokenKind.Number) and TryStrToInt(AToken.Text, Value) and
    (Value >= 0) and (Value <= 255);
  if Result then
    AValue := Value;
end;

function TryRgbCall(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AColor: TRgbColor;
  out ALast: Integer): Boolean;
var
  Parts: array[0..2] of Byte;
  I, Part: Integer;
begin
  // RGB ( n , n , n )
  Result := False;
  I := SignificantIndex(ATokens, AIndex + 1);
  if (I > High(ATokens)) or (ATokens[I].Text <> '(') then
    Exit;
  for Part := 0 to 2 do
  begin
    I := SignificantIndex(ATokens, I + 1);
    if (I > High(ATokens)) or not TryByte(ATokens[I], Parts[Part]) then
      Exit;
    I := SignificantIndex(ATokens, I + 1);
    if I > High(ATokens) then
      Exit;
    if (Part < 2) and (ATokens[I].Text <> ',') or (Part = 2) and (ATokens[I].Text <> ')') then
      Exit;
  end;
  AColor := TRgbColor.Create(Parts[0], Parts[1], Parts[2]);
  ALast := I;
  Result := True;
end;

function TryHex(const AText: string; out AColor: TRgbColor): Boolean;
var
  Value: Int64;
begin
  // Nur $00BBGGRR: acht Stellen mit 00 vorn. Kürzere Hexzahlen sind meist Masken oder Codes.
  Result := (Length(AText) = 9) and (AText[1] = '$') and (Copy(AText, 2, 2) = '00') and
    TryStrToInt64(AText, Value);
  if Result then
    AColor := TRgbColor.FromTColor(Cardinal(Value));
end;

function TryNamed(const AName: string; out AColor: TRgbColor): Boolean;
var
  Named: TNamedColor;
begin
  for Named in NamedColors do
    if SameText(Named.Name, AName) then
    begin
      AColor := FromRgbValue(Named.Value);
      Exit(True);
    end;
  Result := False;
end;

function TrySystem(const AName: string; const AProvider: TSystemColorProvider; out AColor: TRgbColor): Boolean;
var
  Entry: TSystemColor;
begin
  for Entry in SystemColors do
    if SameText(Entry.Name, AName) then
    begin
      if not (Assigned(AProvider) and AProvider(Entry.Index, AColor)) then
        AColor := FromRgbValue(Entry.DefaultValue);
      Exit(True);
    end;
  Result := False;
end;

class function TSourceColors.Find(const AText: string; const ASystemColors: TSystemColorProvider): TArray<TColorMatch>;
var
  Tokens: TArray<TPascalToken>;
  I, Last: Integer;
  Match: TColorMatch;
  Found: Boolean;
begin
  Result := nil;
  Tokens := TPascalLexer.Tokenize(AText);
  I := 0;
  while I <= High(Tokens) do
  begin
    Found := False;
    Last := I;
    case Tokens[I].Kind of
      TPascalTokenKind.Number:
        if TryHex(Tokens[I].Text, Match.Color) then
        begin
          Match.Format := TColorFormat.Hex;
          Found := True;
        end;
      TPascalTokenKind.Identifier:
        if SameText(Tokens[I].Text, 'RGB') and TryRgbCall(Tokens, I, Match.Color, Last) then
        begin
          Match.Format := TColorFormat.Rgb;
          Found := True;
        end
        else if TryNamed(Tokens[I].Text, Match.Color) then
        begin
          Match.Format := TColorFormat.Named;
          Found := True;
        end
        else if TrySystem(Tokens[I].Text, ASystemColors, Match.Color) then
        begin
          Match.Format := TColorFormat.SystemColor;
          Found := True;
        end;
    end;
    if Found then
    begin
      Match.Range := TTextRange.Create(Tokens[I].StartPos, Tokens[Last].EndPos);
      Match.Text := Copy(AText, Tokens[I].Offset + 1, Tokens[Last].Offset + Length(Tokens[Last].Text) - Tokens[I].Offset);
      Result := Result + [Match];
    end;
    I := Last + 1;
  end;
end;

class function TSourceColors.HexText(const AColor: TRgbColor): string;
begin
  Result := '$' + IntToHex(AColor.ToTColor, 8);
end;

class function TSourceColors.NameOf(const AColor: TRgbColor): string;
var
  Named: TNamedColor;
begin
  for Named in NamedColors do
    if FromRgbValue(Named.Value) = AColor then
      Exit(Named.Name);
  Result := '';
end;

class function TSourceColors.Presentations(const AColor: TRgbColor; AFormat: TColorFormat): TArray<TColorPresentation>;

  procedure Add(const AText: string; AKind: TColorFormat);
  var
    Presentation: TColorPresentation;
  begin
    Presentation.Text := AText;
    Presentation.Format := AKind;
    Result := Result + [Presentation];
  end;

var
  Name, Hex, Rgb: string;
begin
  Result := nil;
  Name := NameOf(AColor);
  Hex := HexText(AColor);
  Rgb := Format('RGB(%d, %d, %d)', [AColor.R, AColor.G, AColor.B]);
  // Ausgangsformat zuerst; eine benannte Farbe ohne passenden Namen wird zu Hex.
  case AFormat of
    TColorFormat.Rgb:
      Add(Rgb, TColorFormat.Rgb);
    TColorFormat.Named:
      if Name <> '' then
        Add(Name, TColorFormat.Named);
    TColorFormat.Hex: ;
    TColorFormat.SystemColor: ;
  end;
  Add(Hex, TColorFormat.Hex);
  if (AFormat <> TColorFormat.Rgb) then
    Add(Rgb, TColorFormat.Rgb);
  if (Name <> '') and (AFormat <> TColorFormat.Named) then
    Add(Name, TColorFormat.Named);
end;

end.
