unit Atlas.Common.Lsp.HoverValues;

// Zusatzangaben für den Hover (#38): Zahlen in mehreren Schreibweisen, Werte von Konstanten
// und Hinweise auf veraltete, plattformspezifische oder experimentelle Symbole.

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
    /// <summary>Wert einer Konstantendeklaration "Name = Ausdruck;" als FormatNumber; '' wenn kein Zahlenliteral.</summary>
    class function ConstantValue(const ADeclaration: string): string; static;
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

class function THoverValues.ConstantValue(const ADeclaration: string): string;
var
  Equals, Semicolon: Integer;
  Expression: string;
  Value: Int64;
begin
  Result := '';
  Equals := Pos('=', ADeclaration);
  if Equals = 0 then
    Exit;
  Semicolon := PosEx(';', ADeclaration, Equals);
  if Semicolon = 0 then
    Semicolon := Length(ADeclaration) + 1;
  Expression := Trim(Copy(ADeclaration, Equals + 1, Semicolon - Equals - 1));
  // Angehängte Direktiven wie "deprecated" gehören nicht zum Wert.
  if Pos(' ', Expression) > 0 then
    Expression := Copy(Expression, 1, Pos(' ', Expression) - 1);
  if TryParseNumber(Expression, Value) then
    Result := FormatNumber(Value);
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
