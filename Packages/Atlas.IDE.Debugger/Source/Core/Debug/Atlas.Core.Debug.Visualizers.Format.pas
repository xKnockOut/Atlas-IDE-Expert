unit Atlas.Core.Debug.Visualizers.Format;

// Formatierung der Visualisierer (#835) ohne Debugger, einzeln getestet: Text des Debuggers lesen (Felder,
// Zahlen, Adressen, Bytes), kürzen, Hex-Zeilen, JSON kompakt und als Baum, Farben (VCL, System, Web, Alpha),
// TGUID, Geometrie, Pixel aus einem DIB und die Ersatztexte für Listen und Dictionaries.

interface

uses
  System.SysUtils;

type
  /// <summary>Feld eines Records im Text des Debuggers, z. B. X:10 aus (X:10; Y:20); Name '' bei Array-Elementen.
  /// </summary>
  TAtlasDebugField = record
    Name: string;
    Value: string;
  end;

  TAtlasVisualizerNode = record
    Level: Integer;
    Text: string;
  end;

  /// <summary>Aufbau der Pixel eines DIB für TAtlasVisualizerFormat.DibPixels.</summary>
  TAtlasDibLayout = record
    Width: Integer;
    Height: Integer;
    BitsPerPixel: Integer;
    /// <summary>Bytes je Zeile (ausgerichtet).</summary>
    WidthBytes: Integer;
    /// <summary>Zeilen von unten nach oben (positive Höhe im DIB).</summary>
    BottomUp: Boolean;
    class function Create(AWidth, AHeight, ABitsPerPixel, AWidthBytes: Integer;
      ABottomUp: Boolean): TAtlasDibLayout; static;
  end;

  /// <summary>Formatierung ohne Debugger, einzeln getestet.</summary>
  TAtlasVisualizerFormat = class
  public const
    /// <summary>Trenner der Teile eines Ersatztexts.</summary>
    cSeparator = ' · ';
  public
    /// <summary>Höchstens AMaxLength Zeichen, gekürzt mit „…“.</summary>
    class function Shorten(const AText: string; AMaxLength: Integer): string; static;
    /// <summary>Felder bzw. Elemente der obersten Ebene von (A:1; B:(2, 3)) bzw. (1, 2, 3); False ohne Klammern.
    /// </summary>
    class function ParseFields(const AText: string; out AFields: TArray<TAtlasDebugField>): Boolean; static;
    /// <summary>Wert des Felds AName (ohne Groß-/Kleinschreibung); False ohne.</summary>
    class function FieldValue(const AFields: TArray<TAtlasDebugField>; const AName: string;
      out AValue: string): Boolean; static;
    /// <summary>Ganze Zahl aus dem Text des Debuggers (dezimal, $hex, auch mit Typumwandlung „Pointer($1F)“).
    /// </summary>
    class function ParseInteger(const AText: string; out AValue: Int64): Boolean; static;
    /// <summary>Adresse aus „$0A3F1C20“, „Pointer($…)“ oder „:0A3F1C20“; False bei nil.</summary>
    class function ParseAddress(const AText: string; out AAddress: UInt64): Boolean; static;
    /// <summary>Bytes aus der Array-Anzeige „(72, 101, $6C)“; False, wenn es keine ist.</summary>
    class function ParseByteList(const AText: string; out ABytes: TBytes): Boolean; static;
    /// <summary>Zeichenkette des Debuggers ohne Anführungszeichen ('It''s' → It's, #13 bleibt); sonst der Text.
    /// </summary>
    class function Unquote(const AText: string): string; static;
    /// <summary>Wert eines Objekts statt eines einfachen Werts (Klammern, Adresse)?</summary>
    class function IsStructured(const AText: string): Boolean; static;
    /// <summary>„n Bytes · 48 65 6C 6C 6F · Hello“ mit höchstens AMaxBytes Bytes; nicht druckbare Zeichen als „.“.
    /// </summary>
    class function HexPreview(const ABytes: TBytes; ATotal: Int64; AMaxBytes: Integer): string; static;
    /// <summary>Zeile der Hex-Ansicht ab AOffset: „00000010  48 65 … 6F  Hello“ (16 Bytes je Zeile).</summary>
    class function HexLine(const ABytes: TBytes; AOffset: Integer): string; static;
    class function HexLineCount(ALength: Integer): Integer; static;
    /// <summary>JSON-Text kompakt (ohne Leerraum außerhalb von Zeichenketten).</summary>
    class function CompactJson(const AText: string): string; static;
    /// <summary>JSON als Baum (Schlüssel: Wert, Objekte {n}, Arrays [n]); False bei ungültigem JSON.</summary>
    class function JsonTree(const AText: string; out ANodes: TArray<TAtlasVisualizerNode>): Boolean; static;
    /// <summary>TColor-Wert ($00BBGGRR bzw. Systemfarbe $FF0000xx) als Name (clRed, clWebDodgerBlue, clBtnFace,
    /// clNone, clDefault); '' ohne Namen.</summary>
    class function ColorName(AValue: Int64): string; static;
    /// <summary>TColor als $RRGGBB; Systemfarben und clNone haben keinen.</summary>
    class function ColorRgb(AValue: Int64; out ARgb: Cardinal): Boolean; static;
    /// <summary>„clWebDodgerBlue · $1E90FF“, „$123456“, „clBtnFace“.</summary>
    class function ColorText(AValue: Int64): string; static;
    /// <summary>TAlphaColor ($AARRGGBB) als „claDodgerBlue“ bzw. „$801E90FF“.</summary>
    class function AlphaColorText(AValue: Int64): string; static;
    /// <summary>TGUID aus (D1:…; D2:…; D3:…; D4:(…)) als {XXXXXXXX-XXXX-…}; '' wenn es keiner ist.</summary>
    class function GuidText(const AEvalResult: string): string; static;
    /// <summary>TPoint, TRect, TSize (auch …F) kurz: „(10, 20)“, „(10, 20)–(110, 70)“, „100 × 50“; ''
    /// sonst.</summary>
    class function GeometryText(const ABaseType, AEvalResult: string): string; static;
    /// <summary>Pixel eines DIB (24 oder 32 Bit, Zeilen auf ALayout.WidthBytes ausgerichtet) von oben nach
    /// unten.</summary>
    class function DibPixels(const ABits: TBytes; const ALayout: TAtlasDibLayout;
      out APixels: TArray<Cardinal>): Boolean; static;
    /// <summary>„Klasse · Count = n · [a, b, c, …]“.</summary>
    class function ListText(const AShown: string; ACount: Integer; const AItems: TArray<string>): string; static;
    /// <summary>„Klasse · Count = n · {k: v, …}“.</summary>
    class function DictionaryText(const AShown: string; ACount: Integer;
      const APairs: TArray<string>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections;

type
  TNamedValue = record
    Name: string;
    Value: Cardinal;
  end;

const
  // Feste Farben der VCL (RGB).
  cStandardColors: array[0..19] of TNamedValue = (
    (Name: 'clBlack'; Value: $000000), (Name: 'clMaroon'; Value: $800000), (Name: 'clGreen'; Value: $008000),
    (Name: 'clOlive'; Value: $808000), (Name: 'clNavy'; Value: $000080), (Name: 'clPurple'; Value: $800080),
    (Name: 'clTeal'; Value: $008080), (Name: 'clGray'; Value: $808080), (Name: 'clSilver'; Value: $C0C0C0),
    (Name: 'clRed'; Value: $FF0000), (Name: 'clLime'; Value: $00FF00), (Name: 'clYellow'; Value: $FFFF00),
    (Name: 'clBlue'; Value: $0000FF), (Name: 'clFuchsia'; Value: $FF00FF), (Name: 'clAqua'; Value: $00FFFF),
    (Name: 'clWhite'; Value: $FFFFFF), (Name: 'clMoneyGreen'; Value: $C0DCC0), (Name: 'clSkyBlue'; Value: $A6CAF0),
    (Name: 'clCream'; Value: $FFFBF0), (Name: 'clMedGray'; Value: $A0A0A4));
  // Systemfarben: clXxx = $FF000000 or Index (COLOR_*).
  cSystemColors: array[0..30] of string = ('clScrollBar', 'clBackground', 'clActiveCaption', 'clInactiveCaption',
    'clMenu', 'clWindow', 'clWindowFrame', 'clMenuText', 'clWindowText', 'clCaptionText', 'clActiveBorder',
    'clInactiveBorder', 'clAppWorkSpace', 'clHighlight', 'clHighlightText', 'clBtnFace', 'clBtnShadow',
    'clGrayText', 'clBtnText', 'clInactiveCaptionText', 'clBtnHighlight', 'cl3DDkShadow', 'cl3DLight',
    'clInfoText', 'clInfoBk', '', 'clHotLight', 'clGradientActiveCaption', 'clGradientInactiveCaption',
    'clMenuHighlight', 'clMenuBar');
  // CSS-Farben (RGB), ohne „Grey“-Schreibweisen: clWebXxx bzw. claXxx.
  cWebColors: array[0..139] of TNamedValue = (
    (Name: 'AliceBlue'; Value: $F0F8FF), (Name: 'AntiqueWhite'; Value: $FAEBD7), (Name: 'Aqua'; Value: $00FFFF),
    (Name: 'Aquamarine'; Value: $7FFFD4), (Name: 'Azure'; Value: $F0FFFF), (Name: 'Beige'; Value: $F5F5DC),
    (Name: 'Bisque'; Value: $FFE4C4), (Name: 'Black'; Value: $000000), (Name: 'BlanchedAlmond'; Value: $FFEBCD),
    (Name: 'Blue'; Value: $0000FF), (Name: 'BlueViolet'; Value: $8A2BE2), (Name: 'Brown'; Value: $A52A2A),
    (Name: 'BurlyWood'; Value: $DEB887), (Name: 'CadetBlue'; Value: $5F9EA0), (Name: 'Chartreuse'; Value: $7FFF00),
    (Name: 'Chocolate'; Value: $D2691E), (Name: 'Coral'; Value: $FF7F50), (Name: 'CornflowerBlue'; Value: $6495ED),
    (Name: 'CornSilk'; Value: $FFF8DC), (Name: 'Crimson'; Value: $DC143C), (Name: 'Cyan'; Value: $00FFFF),
    (Name: 'DarkBlue'; Value: $00008B), (Name: 'DarkCyan'; Value: $008B8B),
    (Name: 'DarkGoldenRod'; Value: $B8860B), (Name: 'DarkGray'; Value: $A9A9A9),
    (Name: 'DarkGreen'; Value: $006400), (Name: 'DarkKhaki'; Value: $BDB76B),
    (Name: 'DarkMagenta'; Value: $8B008B), (Name: 'DarkOliveGreen'; Value: $556B2F),
    (Name: 'DarkOrange'; Value: $FF8C00), (Name: 'DarkOrchid'; Value: $9932CC), (Name: 'DarkRed'; Value: $8B0000),
    (Name: 'DarkSalmon'; Value: $E9967A), (Name: 'DarkSeaGreen'; Value: $8FBC8F),
    (Name: 'DarkSlateBlue'; Value: $483D8B), (Name: 'DarkSlateGray'; Value: $2F4F4F),
    (Name: 'DarkTurquoise'; Value: $00CED1), (Name: 'DarkViolet'; Value: $9400D3),
    (Name: 'DeepPink'; Value: $FF1493), (Name: 'DeepSkyBlue'; Value: $00BFFF), (Name: 'DimGray'; Value: $696969),
    (Name: 'DodgerBlue'; Value: $1E90FF), (Name: 'FireBrick'; Value: $B22222),
    (Name: 'FloralWhite'; Value: $FFFAF0), (Name: 'ForestGreen'; Value: $228B22),
    (Name: 'Fuchsia'; Value: $FF00FF), (Name: 'Gainsboro'; Value: $DCDCDC), (Name: 'GhostWhite'; Value: $F8F8FF),
    (Name: 'Gold'; Value: $FFD700), (Name: 'GoldenRod'; Value: $DAA520), (Name: 'Gray'; Value: $808080),
    (Name: 'Green'; Value: $008000), (Name: 'GreenYellow'; Value: $ADFF2F), (Name: 'HoneyDew'; Value: $F0FFF0),
    (Name: 'HotPink'; Value: $FF69B4), (Name: 'IndianRed'; Value: $CD5C5C), (Name: 'Indigo'; Value: $4B0082),
    (Name: 'Ivory'; Value: $FFFFF0), (Name: 'Khaki'; Value: $F0E68C), (Name: 'Lavender'; Value: $E6E6FA),
    (Name: 'LavenderBlush'; Value: $FFF0F5), (Name: 'LawnGreen'; Value: $7CFC00),
    (Name: 'LemonChiffon'; Value: $FFFACD), (Name: 'LightBlue'; Value: $ADD8E6),
    (Name: 'LightCoral'; Value: $F08080), (Name: 'LightCyan'; Value: $E0FFFF),
    (Name: 'LightGoldenRodYellow'; Value: $FAFAD2), (Name: 'LightGray'; Value: $D3D3D3),
    (Name: 'LightGreen'; Value: $90EE90), (Name: 'LightPink'; Value: $FFB6C1),
    (Name: 'LightSalmon'; Value: $FFA07A), (Name: 'LightSeaGreen'; Value: $20B2AA),
    (Name: 'LightSkyBlue'; Value: $87CEFA), (Name: 'LightSlateGray'; Value: $778899),
    (Name: 'LightSteelBlue'; Value: $B0C4DE), (Name: 'LightYellow'; Value: $FFFFE0),
    (Name: 'Lime'; Value: $00FF00), (Name: 'LimeGreen'; Value: $32CD32), (Name: 'Linen'; Value: $FAF0E6),
    (Name: 'Magenta'; Value: $FF00FF), (Name: 'Maroon'; Value: $800000),
    (Name: 'MediumAquamarine'; Value: $66CDAA), (Name: 'MediumBlue'; Value: $0000CD),
    (Name: 'MediumOrchid'; Value: $BA55D3), (Name: 'MediumPurple'; Value: $9370DB),
    (Name: 'MediumSeaGreen'; Value: $3CB371), (Name: 'MediumSlateBlue'; Value: $7B68EE),
    (Name: 'MediumSpringGreen'; Value: $00FA9A), (Name: 'MediumTurquoise'; Value: $48D1CC),
    (Name: 'MediumVioletRed'; Value: $C71585), (Name: 'MidnightBlue'; Value: $191970),
    (Name: 'MintCream'; Value: $F5FFFA), (Name: 'MistyRose'; Value: $FFE4E1), (Name: 'Moccasin'; Value: $FFE4B5),
    (Name: 'NavajoWhite'; Value: $FFDEAD), (Name: 'Navy'; Value: $000080), (Name: 'OldLace'; Value: $FDF5E6),
    (Name: 'Olive'; Value: $808000), (Name: 'OliveDrab'; Value: $6B8E23), (Name: 'Orange'; Value: $FFA500),
    (Name: 'OrangeRed'; Value: $FF4500), (Name: 'Orchid'; Value: $DA70D6), (Name: 'PaleGoldenRod'; Value: $EEE8AA),
    (Name: 'PaleGreen'; Value: $98FB98), (Name: 'PaleTurquoise'; Value: $AFEEEE),
    (Name: 'PaleVioletRed'; Value: $DB7093), (Name: 'PapayaWhip'; Value: $FFEFD5),
    (Name: 'PeachPuff'; Value: $FFDAB9), (Name: 'Peru'; Value: $CD853F), (Name: 'Pink'; Value: $FFC0CB),
    (Name: 'Plum'; Value: $DDA0DD), (Name: 'PowderBlue'; Value: $B0E0E6), (Name: 'Purple'; Value: $800080),
    (Name: 'Red'; Value: $FF0000), (Name: 'RosyBrown'; Value: $BC8F8F), (Name: 'RoyalBlue'; Value: $4169E1),
    (Name: 'SaddleBrown'; Value: $8B4513), (Name: 'Salmon'; Value: $FA8072), (Name: 'SandyBrown'; Value: $F4A460),
    (Name: 'SeaGreen'; Value: $2E8B57), (Name: 'SeaShell'; Value: $FFF5EE), (Name: 'Sienna'; Value: $A0522D),
    (Name: 'Silver'; Value: $C0C0C0), (Name: 'SkyBlue'; Value: $87CEEB), (Name: 'SlateBlue'; Value: $6A5ACD),
    (Name: 'SlateGray'; Value: $708090), (Name: 'Snow'; Value: $FFFAFA), (Name: 'SpringGreen'; Value: $00FF7F),
    (Name: 'SteelBlue'; Value: $4682B4), (Name: 'Tan'; Value: $D2B48C), (Name: 'Teal'; Value: $008080),
    (Name: 'Thistle'; Value: $D8BFD8), (Name: 'Tomato'; Value: $FF6347), (Name: 'Turquoise'; Value: $40E0D0),
    (Name: 'Violet'; Value: $EE82EE), (Name: 'Wheat'; Value: $F5DEB3), (Name: 'White'; Value: $FFFFFF),
    (Name: 'WhiteSmoke'; Value: $F5F5F5), (Name: 'Yellow'; Value: $FFFF00), (Name: 'YellowGreen'; Value: $9ACD32));
  cClNone = $1FFFFFFF;
  cClDefault = $20000000;
  cSystemColorBase = Int64($FF000000);

{ TAtlasVisualizerFormat }

class function TAtlasVisualizerFormat.Shorten(const AText: string; AMaxLength: Integer): string;
begin
  Result := AText;
  if (AMaxLength > 0) and (Length(Result) > AMaxLength) then
  begin
    Result := Copy(Result, 1, Max(AMaxLength - 1, 1)) + '…';
  end;
end;

class function TAtlasVisualizerFormat.ParseFields(const AText: string; out AFields: TArray<TAtlasDebugField>): Boolean;
var
  mText, mPart: string;
  mIndex, mDepth, mStart, mColon: Integer;
  mInString: Boolean;
  mField: TAtlasDebugField;

  procedure AddPart(const APart: string);
  var
    mTrimmed: string;
    mHead: string;
  begin
    mTrimmed := Trim(APart);
    if mTrimmed = '' then
    begin
      Exit;
    end;
    mField := Default(TAtlasDebugField);
    // „Name:Wert“ nur, wenn vor dem ersten Doppelpunkt ein Bezeichner steht (nicht in Zeichenketten).
    mColon := Pos(':', mTrimmed);
    mHead := '';
    if mColon > 1 then
    begin
      mHead := Trim(Copy(mTrimmed, 1, mColon - 1));
    end;
    if (mHead <> '') and IsValidIdent(mHead) then
    begin
      mField.Name := mHead;
      mField.Value := Trim(Copy(mTrimmed, mColon + 1, MaxInt));
    end
    else
    begin
      mField.Value := mTrimmed;
    end;
    AFields := AFields + [mField];
  end;

begin
  AFields := nil;
  mText := Trim(AText);
  Result := (Length(mText) >= 2) and (mText[1] = '(') and (mText[Length(mText)] = ')');
  if not Result then
  begin
    Exit;
  end;
  mText := Copy(mText, 2, Length(mText) - 2);
  mDepth := 0;
  mInString := False;
  mStart := 1;
  for mIndex := 1 to Length(mText) do
  begin
    if mInString then
    begin
      if mText[mIndex] = '''' then
      begin
        mInString := False;
      end;
      Continue;
    end;
    case mText[mIndex] of
      '''':
        mInString := True;
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
      ';', ',':
        if mDepth = 0 then
        begin
          mPart := Copy(mText, mStart, mIndex - mStart);
          AddPart(mPart);
          mStart := mIndex + 1;
        end;
    end;
  end;
  AddPart(Copy(mText, mStart, MaxInt));
end;

class function TAtlasVisualizerFormat.FieldValue(const AFields: TArray<TAtlasDebugField>; const AName: string;
  out AValue: string): Boolean;
var
  mField: TAtlasDebugField;
begin
  AValue := '';
  for mField in AFields do
  begin
    if SameText(mField.Name, AName) then
    begin
      AValue := mField.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasVisualizerFormat.ParseInteger(const AText: string; out AValue: Int64): Boolean;
var
  mText: string;
  mOpen: Integer;
begin
  AValue := 0;
  mText := Trim(AText);
  // Typumwandlung der Anzeige: Pointer($1F), Cardinal(5).
  mOpen := Pos('(', mText);
  if (mOpen > 1) and (mText[Length(mText)] = ')') and IsValidIdent(Copy(mText, 1, mOpen - 1)) then
  begin
    mText := Trim(Copy(mText, mOpen + 1, Length(mText) - mOpen - 1));
  end;
  if (mText <> '') and (mText[1] = ':') then
  begin
    mText := '$' + Copy(mText, 2, MaxInt);
  end;
  Result := (mText <> '') and TryStrToInt64(mText, AValue);
  if not Result and (Length(mText) > 1) and (mText[1] = '$') then
  begin
    // Über Int64 hinaus (Adressen mit gesetztem höchstem Bit): als UInt64.
    Result := TryStrToUInt64(mText, UInt64(AValue));
  end;
end;

class function TAtlasVisualizerFormat.ParseAddress(const AText: string; out AAddress: UInt64): Boolean;
var
  mValue: Int64;
begin
  AAddress := 0;
  Result := ParseInteger(AText, mValue) and (mValue <> 0);
  if Result then
  begin
    AAddress := UInt64(mValue);
  end;
end;

class function TAtlasVisualizerFormat.ParseByteList(const AText: string; out ABytes: TBytes): Boolean;
var
  mFields: TArray<TAtlasDebugField>;
  mField: TAtlasDebugField;
  mValue: Int64;
  mIndex: Integer;
begin
  ABytes := nil;
  if Trim(AText) = '()' then
  begin
    Exit(True);
  end;
  Result := ParseFields(AText, mFields);
  if not Result then
  begin
    Exit;
  end;
  SetLength(ABytes, Length(mFields));
  mIndex := 0;
  for mField in mFields do
  begin
    // „…“ am Ende einer gekürzten Anzeige: was davor steht, gilt.
    if (mField.Value = '...') or (mField.Value = '…') then
    begin
      Break;
    end;
    if (mField.Name <> '') or not ParseInteger(mField.Value, mValue) or (mValue < 0) or (mValue > 255) then
    begin
      ABytes := nil;
      Exit(False);
    end;
    ABytes[mIndex] := Byte(mValue);
    Inc(mIndex);
  end;
  SetLength(ABytes, mIndex);
end;

class function TAtlasVisualizerFormat.Unquote(const AText: string): string;
var
  mText: string;
begin
  mText := Trim(AText);
  if (Length(mText) >= 2) and (mText[1] = '''') and (mText[Length(mText)] = '''') then
  begin
    Result := StringReplace(Copy(mText, 2, Length(mText) - 2), '''''', '''', [rfReplaceAll]);
  end
  else
  begin
    Result := mText;
  end;
end;

class function TAtlasVisualizerFormat.IsStructured(const AText: string): Boolean;
var
  mText: string;
begin
  mText := Trim(AText);
  Result := (mText <> '') and ((mText[1] = '(') or (mText[1] = '$') or (mText[1] = ':') or (mText[1] = '{'));
end;

function Printable(AValue: Byte): Char;
begin
  if (AValue >= 32) and (AValue < 127) then
  begin
    Result := Char(AValue);
  end
  else
  begin
    Result := '.';
  end;
end;

class function TAtlasVisualizerFormat.HexPreview(const ABytes: TBytes; ATotal: Int64; AMaxBytes: Integer): string;
var
  mCount, mIndex: Integer;
  mHex, mText: string;
begin
  mCount := Min(Length(ABytes), AMaxBytes);
  mHex := '';
  mText := '';
  for mIndex := 0 to mCount - 1 do
  begin
    if mHex <> '' then
    begin
      mHex := mHex + ' ';
    end;
    mHex := mHex + IntToHex(ABytes[mIndex], 2);
    mText := mText + Printable(ABytes[mIndex]);
  end;
  if ATotal > mCount then
  begin
    mHex := mHex + ' …';
    mText := mText + '…';
  end;
  Result := Format('%d Bytes', [ATotal]);
  if mHex <> '' then
  begin
    Result := Result + cSeparator + mHex + cSeparator + mText;
  end;
end;

class function TAtlasVisualizerFormat.HexLineCount(ALength: Integer): Integer;
begin
  Result := (ALength + 15) div 16;
end;

class function TAtlasVisualizerFormat.HexLine(const ABytes: TBytes; AOffset: Integer): string;
var
  mIndex: Integer;
  mHex, mText: string;
begin
  mHex := '';
  mText := '';
  for mIndex := AOffset to AOffset + 15 do
  begin
    if mIndex = AOffset + 8 then
    begin
      mHex := mHex + ' ';
    end;
    if mIndex < Length(ABytes) then
    begin
      mHex := mHex + IntToHex(ABytes[mIndex], 2) + ' ';
      mText := mText + Printable(ABytes[mIndex]);
    end
    else
    begin
      mHex := mHex + '   ';
    end;
  end;
  Result := IntToHex(AOffset, 8) + '  ' + mHex + ' ' + mText;
end;

class function TAtlasVisualizerFormat.CompactJson(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mInString, mEscaped: Boolean;
  C: Char;
begin
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mInString := False;
    mEscaped := False;
    for mIndex := 1 to Length(AText) do
    begin
      C := AText[mIndex];
      if mInString then
      begin
        mBuilder.Append(C);
        if mEscaped then
        begin
          mEscaped := False;
        end
        else if C = '\' then
        begin
          mEscaped := True;
        end
        else if C = '"' then
        begin
          mInString := False;
        end;
        Continue;
      end;
      if C = '"' then
      begin
        mInString := True;
      end;
      if CharInSet(C, [' ', #9, #10, #13]) then
      begin
        Continue;
      end;
      mBuilder.Append(C);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure AddJsonNodes(AValue: TJSONValue; const ALabel: string; ALevel: Integer;
  var ANodes: TArray<TAtlasVisualizerNode>);
var
  mNode: TAtlasVisualizerNode;
  mPair: TJSONPair;
  mIndex: Integer;
  mPrefix: string;
begin
  mNode.Level := ALevel;
  mPrefix := '';
  if ALabel <> '' then
  begin
    mPrefix := ALabel + ': ';
  end;
  if AValue is TJSONObject then
  begin
    mNode.Text := mPrefix + Format('{%d}', [TJSONObject(AValue).Count]);
    ANodes := ANodes + [mNode];
    for mIndex := 0 to TJSONObject(AValue).Count - 1 do
    begin
      mPair := TJSONObject(AValue).Pairs[mIndex];
      AddJsonNodes(mPair.JsonValue, mPair.JsonString.Value, ALevel + 1, ANodes);
    end;
  end
  else if AValue is TJSONArray then
  begin
    mNode.Text := mPrefix + Format('[%d]', [TJSONArray(AValue).Count]);
    ANodes := ANodes + [mNode];
    for mIndex := 0 to TJSONArray(AValue).Count - 1 do
    begin
      AddJsonNodes(TJSONArray(AValue).Items[mIndex], Format('[%d]', [mIndex]), ALevel + 1, ANodes);
    end;
  end
  else
  begin
    mNode.Text := mPrefix + AValue.ToJSON;
    ANodes := ANodes + [mNode];
  end;
end;

class function TAtlasVisualizerFormat.JsonTree(const AText: string; out ANodes: TArray<TAtlasVisualizerNode>): Boolean;
var
  mValue: TJSONValue;
begin
  ANodes := nil;
  mValue := TJSONObject.ParseJSONValue(AText);
  Result := mValue <> nil;
  if not Result then
  begin
    Exit;
  end;
  try
    AddJsonNodes(mValue, '', 0, ANodes);
  finally
    mValue.Free;
  end;
end;

function SwapRedBlue(AValue: Cardinal): Cardinal;
begin
  Result := ((AValue and $FF) shl 16) or (AValue and $FF00) or ((AValue shr 16) and $FF);
end;

class function TAtlasVisualizerFormat.ColorRgb(AValue: Int64; out ARgb: Cardinal): Boolean;
begin
  ARgb := 0;
  Result := (AValue >= 0) and (AValue <= $FFFFFF);
  if Result then
  begin
    ARgb := SwapRedBlue(Cardinal(AValue));
  end;
end;

/// <summary>Name einer Standard- oder Web-Farbe mit dem RGB-Wert ARgb; '' ohne Namen.</summary>
function RgbName(ARgb: Cardinal): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cStandardColors) to High(cStandardColors) do
  begin
    if cStandardColors[mIndex].Value = ARgb then
    begin
      Exit(cStandardColors[mIndex].Name);
    end;
  end;
  Result := '';
  for mIndex := Low(cWebColors) to High(cWebColors) do
  begin
    if cWebColors[mIndex].Value = ARgb then
    begin
      Exit('clWeb' + cWebColors[mIndex].Name);
    end;
  end;
end;

class function TAtlasVisualizerFormat.ColorName(AValue: Int64): string;
var
  mRgb: Cardinal;
  mValue: Int64;
begin
  Result := '';
  mValue := AValue;
  // TColor ist vorzeichenbehaftet: Systemfarben kommen als -16777201 usw.
  if mValue < 0 then
  begin
    mValue := mValue + $100000000;
  end;
  if mValue = cClNone then
  begin
    Result := 'clNone';
  end
  else if mValue = cClDefault then
  begin
    Result := 'clDefault';
  end
  else if (mValue >= cSystemColorBase) and (mValue <= cSystemColorBase + High(cSystemColors)) then
  begin
    Result := cSystemColors[mValue - cSystemColorBase];
  end
  else if ColorRgb(mValue, mRgb) then
  begin
    Result := RgbName(mRgb);
  end;
end;

class function TAtlasVisualizerFormat.ColorText(AValue: Int64): string;
var
  mName: string;
  mRgb: Cardinal;
  mValue: Int64;
begin
  mName := ColorName(AValue);
  mValue := AValue;
  if mValue < 0 then
  begin
    mValue := mValue + $100000000;
  end;
  if not ColorRgb(mValue, mRgb) then
  begin
    Result := mName;
    if Result = '' then
    begin
      Result := '$' + IntToHex(mValue, 8);
    end;
    Exit;
  end;
  Result := '$' + IntToHex(mRgb, 6);
  if mName <> '' then
  begin
    Result := mName + cSeparator + Result;
  end;
end;

class function TAtlasVisualizerFormat.AlphaColorText(AValue: Int64): string;
var
  mValue: Cardinal;
  mIndex: Integer;
begin
  mValue := Cardinal(AValue and $FFFFFFFF);
  Result := '$' + IntToHex(mValue, 8);
  if mValue = 0 then
  begin
    Exit('claNull');
  end;
  if (mValue shr 24) <> $FF then
  begin
    Exit;
  end;
  for mIndex := Low(cWebColors) to High(cWebColors) do
  begin
    if cWebColors[mIndex].Value = (mValue and $FFFFFF) then
    begin
      Exit('cla' + cWebColors[mIndex].Name + cSeparator + Result);
    end;
  end;
end;

/// <summary>Feld AName aus AFields als ganze Zahl.</summary>
function FieldInteger(const AFields: TArray<TAtlasDebugField>; const AName: string; out AValue: Int64): Boolean;
var
  mText: string;
begin
  AValue := 0;
  Result := TAtlasVisualizerFormat.FieldValue(AFields, AName, mText) and
    TAtlasVisualizerFormat.ParseInteger(mText, AValue);
end;

class function TAtlasVisualizerFormat.GuidText(const AEvalResult: string): string;
var
  mFields, mBytes: TArray<TAtlasDebugField>;
  mText: string;
  mD1, mD2, mD3, mValue: Int64;
  mGuid: TGUID;
  mIndex: Integer;
begin
  Result := '';
  if not ParseFields(AEvalResult, mFields) or not FieldInteger(mFields, 'D1', mD1) or
    not FieldInteger(mFields, 'D2', mD2) or not FieldInteger(mFields, 'D3', mD3) then
  begin
    Exit;
  end;
  if not FieldValue(mFields, 'D4', mText) or not ParseFields(mText, mBytes) or (Length(mBytes) <> 8) then
  begin
    Exit;
  end;
  mGuid.D1 := Cardinal(mD1);
  mGuid.D2 := Word(mD2);
  mGuid.D3 := Word(mD3);
  for mIndex := 0 to 7 do
  begin
    if not ParseInteger(mBytes[mIndex].Value, mValue) then
    begin
      Exit;
    end;
    mGuid.D4[mIndex] := Byte(mValue);
  end;
  Result := GUIDToString(mGuid);
end;

function Number(const AText: string): string;
var
  mValue: Double;
  mSettings: TFormatSettings;
begin
  // Ganze Zahlen wie angezeigt; Gleitkomma ohne überflüssige Stellen.
  Result := Trim(AText);
  mSettings := TFormatSettings.Invariant;
  if (Pos('.', Result) > 0) or (Pos('E', UpperCase(Result)) > 0) then
  begin
    if TryStrToFloat(Result, mValue, mSettings) then
    begin
      Result := FloatToStr(mValue, mSettings);
    end;
  end;
end;

function PointText(const AFields: TArray<TAtlasDebugField>): string;
var
  mX, mY: string;
begin
  Result := '';
  if TAtlasVisualizerFormat.FieldValue(AFields, 'X', mX) and TAtlasVisualizerFormat.FieldValue(AFields, 'Y', mY) then
  begin
    Result := Format('(%s, %s)', [Number(mX), Number(mY)]);
  end;
end;

function RectText(const AFields: TArray<TAtlasDebugField>): string;
var
  mLeft, mTop, mRight, mBottom: string;
begin
  Result := '';
  if TAtlasVisualizerFormat.FieldValue(AFields, 'Left', mLeft) and
    TAtlasVisualizerFormat.FieldValue(AFields, 'Top', mTop) and
    TAtlasVisualizerFormat.FieldValue(AFields, 'Right', mRight) and
    TAtlasVisualizerFormat.FieldValue(AFields, 'Bottom', mBottom) then
  begin
    Result := Format('(%s, %s)–(%s, %s)', [Number(mLeft), Number(mTop), Number(mRight), Number(mBottom)]);
  end;
end;

function SizeText(const AFields: TArray<TAtlasDebugField>): string;
var
  mWidth, mHeight: string;
begin
  Result := '';
  if (TAtlasVisualizerFormat.FieldValue(AFields, 'cx', mWidth) and
    TAtlasVisualizerFormat.FieldValue(AFields, 'cy', mHeight)) or
    (TAtlasVisualizerFormat.FieldValue(AFields, 'Width', mWidth) and
    TAtlasVisualizerFormat.FieldValue(AFields, 'Height', mHeight)) then
  begin
    Result := Format('%s × %s', [Number(mWidth), Number(mHeight)]);
  end;
end;

class function TAtlasVisualizerFormat.GeometryText(const ABaseType, AEvalResult: string): string;
var
  mFields: TArray<TAtlasDebugField>;
begin
  Result := '';
  if not ParseFields(AEvalResult, mFields) then
  begin
    Exit;
  end;
  if MatchText(ABaseType, ['TPoint', 'TPointF', 'TSmallPoint']) then
  begin
    Result := PointText(mFields);
  end
  else if MatchText(ABaseType, ['TRect', 'TRectF']) then
  begin
    Result := RectText(mFields);
  end
  else if MatchText(ABaseType, ['TSize', 'TSizeF']) then
  begin
    Result := SizeText(mFields);
  end;
end;

{ TAtlasDibLayout }

class function TAtlasDibLayout.Create(AWidth, AHeight, ABitsPerPixel, AWidthBytes: Integer;
  ABottomUp: Boolean): TAtlasDibLayout;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.BitsPerPixel := ABitsPerPixel;
  Result.WidthBytes := AWidthBytes;
  Result.BottomUp := ABottomUp;
end;

class function TAtlasVisualizerFormat.DibPixels(const ABits: TBytes; const ALayout: TAtlasDibLayout;
  out APixels: TArray<Cardinal>): Boolean;
var
  X, Y, mRow, mOffset, mStep: Integer;
  mAlpha: Cardinal;
  mWidth, mHeight, mWidthBytes: Integer;
begin
  APixels := nil;
  mWidth := ALayout.Width;
  mHeight := ALayout.Height;
  mWidthBytes := ALayout.WidthBytes;
  Result := (mWidth > 0) and (mHeight > 0) and ((ALayout.BitsPerPixel = 24) or (ALayout.BitsPerPixel = 32)) and
    (mWidthBytes >= mWidth * (ALayout.BitsPerPixel div 8)) and (Int64(mWidthBytes) * mHeight <= Length(ABits));
  if not Result then
  begin
    Exit;
  end;
  mStep := ALayout.BitsPerPixel div 8;
  SetLength(APixels, mWidth * mHeight);
  for Y := 0 to mHeight - 1 do
  begin
    if ALayout.BottomUp then
    begin
      mRow := mHeight - 1 - Y;
    end
    else
    begin
      mRow := Y;
    end;
    for X := 0 to mWidth - 1 do
    begin
      // DIB: Blau, Grün, Rot (, Alpha).
      mOffset := mRow * mWidthBytes + X * mStep;
      mAlpha := $FF;
      if mStep = 4 then
      begin
        mAlpha := ABits[mOffset + 3];
      end;
      APixels[Y * mWidth + X] := (mAlpha shl 24) or (Cardinal(ABits[mOffset + 2]) shl 16) or
        (Cardinal(ABits[mOffset + 1]) shl 8) or ABits[mOffset];
    end;
  end;
end;

class function TAtlasVisualizerFormat.ListText(const AShown: string; ACount: Integer;
  const AItems: TArray<string>): string;
begin
  Result := Format('%s · Count = %d', [AShown, ACount]);
  if Length(AItems) > 0 then
  begin
    Result := Result + cSeparator + '[' + string.Join(', ', AItems);
    if ACount > Length(AItems) then
    begin
      Result := Result + ', …';
    end;
    Result := Result + ']';
  end;
end;

class function TAtlasVisualizerFormat.DictionaryText(const AShown: string; ACount: Integer;
  const APairs: TArray<string>): string;
begin
  Result := Format('%s · Count = %d', [AShown, ACount]);
  if Length(APairs) > 0 then
  begin
    Result := Result + cSeparator + '{' + string.Join(', ', APairs);
    if ACount > Length(APairs) then
    begin
      Result := Result + ', …';
    end;
    Result := Result + '}';
  end;
end;

end.
