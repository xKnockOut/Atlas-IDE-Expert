unit Atlas.Common.Lsp.HoverValues;

// Zusatzangaben für den Hover (#38): Zahlen in mehreren Schreibweisen, Werte von Konstanten
// (Zahlen, Mengen, Texte auch aus mehreren Teilen wie bei Resourcestrings), Basistyp von
// Mengentypen und Hinweise auf veraltete, plattformspezifische oder experimentelle Symbole.

interface

uses
  System.SysUtils;

type
  THoverValues = record
  public
    /// <summary>Dezimal, $Hex, %Binär und &amp;Oktal, mit optionalem Vorzeichen.</summary>
    class function TryParseNumber(const AText: string; out AValue: Int64): Boolean; static;
    /// <summary>"15 · $0F · %1111"</summary>
    class function FormatNumber(AValue: Int64): string; static;
    /// <summary>Wert einer Konstantendeklaration "Name = Ausdruck;": Zahl als FormatNumber, Menge als
    /// SetValue, Text als StringValue; '' bei anderen Ausdrücken.</summary>
    class function ConstantValue(const ADeclaration: string): string; static;
    /// <summary>Ausdruck hinter "=" bis zum letzten ";", ohne angehängte Hinweis-Direktiven; '' ohne "=".
    /// </summary>
    class function ConstantExpression(const ADeclaration: string): string; static;
    /// <summary>"[fsBold, fsItalic] · 2 Elemente"; '' wenn AExpression keine Mengenkonstante ist.</summary>
    class function SetValue(const AExpression: string): string; static;
    /// <summary>Text aus Literalen, #13#10, #$41 und "+" als 'Text' (Zeilenumbruch als ⏎); '' bei anderen
    /// Ausdrücken.</summary>
    class function StringValue(const AExpression: string): string; static;
    /// <summary>Basistyp eines Mengentyps "TFoo = set of TBar;" bzw. "set of (A, B)"; False sonst.</summary>
    class function SetBaseType(const ADeclaration: string; out ABaseType: string): Boolean; static;
    /// <summary>Anzahl möglicher Elemente für den Basistyp, soweit ohne Index bekannt: Aufzählung in
    /// Klammern, Teilbereich aus Zahlen oder Zeichen, Byte, Boolean, AnsiChar …; -1 sonst.</summary>
    class function BaseTypeCount(const ABaseType: string): Integer; static;
    /// <summary>Hinweis zu deprecated/platform/experimental in der Deklaration; '' ohne Direktive.</summary>
    class function Deprecation(const ADeclaration: string): string; static;
  end;

implementation

uses
  System.StrUtils;

function DigitValue(AChar: Char): Integer;
begin
  case AChar of
    '0'..'9': Result := Ord(AChar) - Ord('0');
    'a'..'f': Result := Ord(AChar) - Ord('a') + 10;
    'A'..'F': Result := Ord(AChar) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

class function THoverValues.TryParseNumber(const AText: string; out AValue: Int64): Boolean;
var
  Text: string;
  Base, Index, Digit: Integer;
  Negative: Boolean;
  Value: UInt64;
begin
  AValue := 0;
  Text := Trim(AText);
  Negative := StartsStr('-', Text);
  if Negative or StartsStr('+', Text) then
    Text := Trim(Copy(Text, 2, MaxInt));
  Base := 10;
  if StartsStr('$', Text) then
    Base := 16
  else if StartsStr('%', Text) then
    Base := 2
  else if StartsStr('&', Text) then
    Base := 8;
  if Base <> 10 then
    Text := Copy(Text, 2, MaxInt);
  // Ziffertrenner ab Delphi 11: 1_000
  Text := StringReplace(Text, '_', '', [rfReplaceAll]);
  if Text = '' then
    Exit(False);
  Value := 0;
  for Index := 1 to Length(Text) do
  begin
    Digit := DigitValue(Text[Index]);
    if (Digit < 0) or (Digit >= Base) then
      Exit(False);
    if Value > (High(UInt64) - UInt64(Digit)) div UInt64(Base) then
      Exit(False);
    Value := Value * UInt64(Base) + UInt64(Digit);
  end;
  if Negative then
    AValue := -Int64(Value)
  else
    AValue := Int64(Value);
  Result := True;
end;

class function THoverValues.FormatNumber(AValue: Int64): string;
var
  Hex, Binary: string;
  Value: UInt64;
begin
  Value := UInt64(AValue);
  // Ohne Vorzeichen auf Byte, Word, Cardinal bzw. Int64 auffüllen.
  if (AValue >= 0) and (AValue <= High(Byte)) then
    Hex := IntToHex(AValue, 2)
  else if (AValue >= 0) and (AValue <= High(Word)) then
    Hex := IntToHex(AValue, 4)
  else if (AValue >= 0) and (AValue <= High(Cardinal)) then
    Hex := IntToHex(AValue, 8)
  else
    Hex := IntToHex(AValue, 16);
  Binary := '';
  repeat
    Binary := Char(Ord('0') + Integer(Value and 1)) + Binary;
    Value := Value shr 1;
  until Value = 0;
  Result := IntToStr(AValue) + ' · $' + Hex + ' · %' + Binary;
end;

const
  HintWords: array[0..3] of string = ('deprecated', 'platform', 'experimental', 'library');

/// <summary>Teile von AText auf oberster Ebene (außerhalb von Strings und Klammern), getrennt durch ADelimiter.
/// </summary>
function SplitTop(const AText: string; ADelimiter: Char): TArray<string>;
var
  Index, Depth, Start: Integer;
  InString: Boolean;
begin
  Result := nil;
  Depth := 0;
  InString := False;
  Start := 1;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = '''' then
      InString := not InString
    else if InString then
      Continue
    else if CharInSet(AText[Index], ['(', '[']) then
      Inc(Depth)
    else if CharInSet(AText[Index], [')', ']']) then
      Dec(Depth)
    else if (AText[Index] = ADelimiter) and (Depth = 0) then
    begin
      Result := Result + [Trim(Copy(AText, Start, Index - Start))];
      Start := Index + 1;
    end;
  end;
  Result := Result + [Trim(Copy(AText, Start, MaxInt))];
end;

/// <summary>Position des ersten AChar auf oberster Ebene; 0 ohne.</summary>
function PosTop(AChar: Char; const AText: string): Integer;
var
  Index, Depth: Integer;
  InString: Boolean;
begin
  Depth := 0;
  InString := False;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = '''' then
      InString := not InString
    else if InString then
      Continue
    else if (AText[Index] = AChar) and (Depth = 0) then
      Exit(Index)
    else if CharInSet(AText[Index], ['(', '[']) then
      Inc(Depth)
    else if CharInSet(AText[Index], [')', ']']) then
      Dec(Depth);
  end;
  Result := 0;
end;

class function THoverValues.ConstantExpression(const ADeclaration: string): string;
var
  Equals, Index: Integer;
  Parts: TArray<string>;
  Last, Word: string;
  Changed: Boolean;
begin
  Result := '';
  Equals := PosTop('=', ADeclaration);
  if Equals = 0 then
    Exit;
  // Bis zum ersten ";" auf oberster Ebene; die Hinweise stehen davor oder dahinter.
  Parts := SplitTop(Copy(ADeclaration, Equals + 1, MaxInt), ';');
  Result := Parts[0];
  // Angehängte Direktiven wie "deprecated 'Grund'" gehören nicht zum Wert.
  repeat
    Changed := False;
    Last := Result;
    if EndsStr('''', Last) then
    begin
      Index := Length(Last) - 1;
      while (Index > 0) and (Last[Index] <> '''') do
        Dec(Index);
      if (Index > 1) and EndsText('deprecated', TrimRight(Copy(Last, 1, Index - 1))) then
        Last := TrimRight(Copy(Last, 1, Index - 1));
    end;
    for Word in HintWords do
      if EndsText(' ' + Word, Last) then
      begin
        Result := TrimRight(Copy(Last, 1, Length(Last) - Length(Word)));
        Changed := True;
        Break;
      end;
  until not Changed;
end;

class function THoverValues.ConstantValue(const ADeclaration: string): string;
var
  Expression: string;
  Value: Int64;
begin
  Expression := ConstantExpression(ADeclaration);
  Result := '';
  if Expression = '' then
    Exit;
  if TryParseNumber(Expression, Value) then
    Exit(FormatNumber(Value));
  Result := SetValue(Expression);
  if Result = '' then
    Result := StringValue(Expression);
end;

/// <summary>Ordinalwert eines Zahlen- oder Zeichenliterals ('a', #65, 10); False sonst.</summary>
function TryOrdinal(const AText: string; out AValue: Int64): Boolean;
var
  Text: string;
begin
  Text := Trim(AText);
  if (Length(Text) = 3) and (Text[1] = '''') and (Text[3] = '''') then
  begin
    AValue := Ord(Text[2]);
    Exit(True);
  end;
  if StartsStr('#', Text) then
    Exit(THoverValues.TryParseNumber(Copy(Text, 2, MaxInt), AValue));
  Result := THoverValues.TryParseNumber(Text, AValue);
end;

class function THoverValues.SetValue(const AExpression: string): string;
var
  Text, Element, Low_, High_: string;
  Elements: TArray<string>;
  Count, Range: Integer;
  First, Last: Int64;
  Countable: Boolean;
begin
  Result := '';
  Text := Trim(AExpression);
  if (Length(Text) < 2) or (Text[1] <> '[') or (Text[Length(Text)] <> ']') or
    (PosTop(']', Copy(Text, 2, Length(Text) - 2)) > 0) then
    Exit;
  Text := Trim(Copy(Text, 2, Length(Text) - 2));
  if Text = '' then
    Exit('[] · leer');
  Elements := SplitTop(Text, ',');
  Count := 0;
  Countable := True;
  for Element in Elements do
  begin
    Range := Pos('..', Element);
    if Range = 0 then
    begin
      Inc(Count);
      Continue;
    end;
    Low_ := Trim(Copy(Element, 1, Range - 1));
    High_ := Trim(Copy(Element, Range + 2, MaxInt));
    if TryOrdinal(Low_, First) and TryOrdinal(High_, Last) and (Last >= First) then
      Inc(Count, Integer(Last - First + 1))
    else
      Countable := False;
  end;
  Result := '[' + string.Join(', ', Elements) + ']';
  if not Countable then
    Exit;
  if Count = 1 then
    Result := Result + ' · 1 Element'
  else
    Result := Result + ' · ' + IntToStr(Count) + ' Elemente';
end;

class function THoverValues.StringValue(const AExpression: string): string;
var
  Part, Text: string;
  Index, Close: Integer;
  Code: Int64;
  Builder: TStringBuilder;
begin
  Result := '';
  Builder := TStringBuilder.Create;
  try
    for Part in SplitTop(AExpression, '+') do
    begin
      Text := Part;
      if Text = '' then
        Exit;
      // Eine Folge aus 'Literal' und #Code ohne Leerraum dazwischen.
      Index := 1;
      while Index <= Length(Text) do
      begin
        if Text[Index] = '''' then
        begin
          Close := Index + 1;
          while Close <= Length(Text) do
          begin
            if Text[Close] = '''' then
            begin
              if (Close < Length(Text)) and (Text[Close + 1] = '''') then
              begin
                Builder.Append('''');
                Inc(Close, 2);
                Continue;
              end;
              Break;
            end;
            Builder.Append(Text[Close]);
            Inc(Close);
          end;
          if Close > Length(Text) then
            Exit;
          Index := Close + 1;
        end
        else if Text[Index] = '#' then
        begin
          Close := Index + 1;
          while (Close <= Length(Text)) and CharInSet(Text[Close], ['$', '0'..'9', 'a'..'f', 'A'..'F']) do
            Inc(Close);
          if not TryParseNumber(Copy(Text, Index + 1, Close - Index - 1), Code) or (Code < 0) or
            (Code > $FFFF) then
            Exit;
          Builder.Append(Char(Code));
          Index := Close;
        end
        else
          Exit;
      end;
    end;
    Text := Builder.ToString;
  finally
    Builder.Free;
  end;
  Text := StringReplace(Text, #13#10, '⏎', [rfReplaceAll]);
  Text := StringReplace(Text, #10, '⏎', [rfReplaceAll]);
  Text := StringReplace(Text, #13, '⏎', [rfReplaceAll]);
  Result := '''' + Text + '''';
end;

class function THoverValues.SetBaseType(const ADeclaration: string; out ABaseType: string): Boolean;
var
  Expression, Lower: string;
begin
  ABaseType := '';
  Expression := ConstantExpression(ADeclaration);
  Lower := LowerCase(Expression);
  Result := StartsStr('set of ', Lower) or StartsStr('packed set of ', Lower);
  if Result then
    ABaseType := Trim(Copy(Expression, Pos(' of ', Lower) + 4, MaxInt));
end;

class function THoverValues.BaseTypeCount(const ABaseType: string): Integer;
var
  Text: string;
  Range: Integer;
  First, Last: Int64;
begin
  Result := -1;
  Text := Trim(ABaseType);
  if StartsStr('(', Text) and EndsStr(')', Text) then
    Exit(Length(SplitTop(Copy(Text, 2, Length(Text) - 2), ',')));
  Range := Pos('..', Text);
  if Range > 0 then
  begin
    if TryOrdinal(Copy(Text, 1, Range - 1), First) and TryOrdinal(Copy(Text, Range + 2, MaxInt), Last) and
      (Last >= First) then
      Result := Integer(Last - First + 1);
    Exit;
  end;
  if SameText(Text, 'Boolean') or SameText(Text, 'ByteBool') then
    Result := 2
  else if SameText(Text, 'Byte') or SameText(Text, 'ShortInt') or SameText(Text, 'AnsiChar') or
    SameText(Text, 'Char') or SameText(Text, 'UInt8') or SameText(Text, 'Int8') then
    // set of Char gilt als set of AnsiChar (Warnung W1050).
    Result := 256;
end;

class function THoverValues.Deprecation(const ADeclaration: string): string;
var
  Index, Start, Close: Integer;
  Word, Message: string;
  InString: Boolean;
begin
  Result := '';
  InString := False;
  Index := 1;
  while Index <= Length(ADeclaration) do
  begin
    if ADeclaration[Index] = '''' then
    begin
      InString := not InString;
      Inc(Index);
      Continue;
    end;
    if InString or not CharInSet(ADeclaration[Index], ['a'..'z', 'A'..'Z', '_']) or
      ((Index > 1) and CharInSet(ADeclaration[Index - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_', '.'])) then
    begin
      Inc(Index);
      Continue;
    end;
    Start := Index;
    while (Index <= Length(ADeclaration)) and CharInSet(ADeclaration[Index], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
      Inc(Index);
    Word := LowerCase(Copy(ADeclaration, Start, Index - Start));
    // Direktiven stehen vor ";", einem String oder am Ende; Namen wie "Platform: string" nicht.
    Close := Index;
    while (Close <= Length(ADeclaration)) and (ADeclaration[Close] = ' ') do
      Inc(Close);
    if (Close <= Length(ADeclaration)) and not CharInSet(ADeclaration[Close], [';', '''']) then
      Continue;
    if Word = 'deprecated' then
    begin
      // deprecated 'Stattdessen Bar verwenden'
      Message := '';
      Start := Index;
      while (Start <= Length(ADeclaration)) and (ADeclaration[Start] = ' ') do
        Inc(Start);
      if (Start <= Length(ADeclaration)) and (ADeclaration[Start] = '''') then
      begin
        Close := PosEx('''', ADeclaration, Start + 1);
        if Close > 0 then
          Message := Copy(ADeclaration, Start + 1, Close - Start - 1);
      end;
      Result := '**Veraltet**';
      if Message <> '' then
        Result := Result + ': ' + Message;
      Exit;
    end;
    if Word = 'platform' then
      Exit('**Plattformspezifisch**');
    if Word = 'experimental' then
      Exit('**Experimentell**');
  end;
end;

end.
