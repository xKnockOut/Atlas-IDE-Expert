unit Atlas.Core.Editor.PatternContinuation;

// Muster fortsetzen (#671), ohne Open Tools API und ohne Server: Haben die
// letzten Zeilen derselben Einrückung dieselbe Token-Folge und unterscheiden
// sie sich nur an einzelnen Stellen, deren Werte eine Folge bilden, schlägt
// Suggest die nächste Zeile vor. Rein lokal und tokenbasiert.
// - Verglichen wird der längste Lauf von höchstens MaxLines Zeilen direkt über
//   der Cursorzeile, der dieselbe Form hat; er muss mindestens AMinLines lang
//   sein.
// - Folgen: Ganzzahlen mit fester Schrittweite (auch negativ und hexadezimal,
//   "$0A" behält Stellen und Schreibweise), Zeichen ('A', 'B' → 'C'),
//   Bezeichner mit hochzählender Nummer (Edit1, Edit2 → Edit3; nur wenn es den
//   neuen Namen gibt oder die Zeile ihn deklariert) und Werte eines
//   Aufzählungstyps in Deklarationsreihenfolge (über AEnums; am Ende des Typs
//   kein Vorschlag).
// - Strings, die sich ohne Folge unterscheiden, werden leer ('') und sind
//   freie Felder; der erste ist der Tab-Stopp.
// - Unterscheiden sich Bezeichner ohne erkennbare Folge, gibt es keinen
//   Vorschlag (mehrdeutig).
// LocalEnumValues findet Aufzählungstypen im Text selbst; was dort fehlt,
// fragt die IDE beim Server nach.

interface

uses
  System.SysUtils;

type
  /// <summary>Werte des Aufzählungstyps, zu dem AMember gehört (in Deklarationsreihenfolge); nil, wenn unbekannt.
  /// ALine, ACharacter: Stelle des Werts im Text (0-basiert).</summary>
  TAtlasEnumLookup = reference to function(const AMember: string; ALine, ACharacter: Integer): TArray<string>;
  /// <summary>Gibt es den Bezeichner AName im Text bzw. Projekt?</summary>
  TAtlasNameExists = reference to function(const AName: string): Boolean;

  TAtlasPatternSuggestion = record
    /// <summary>Die neue Zeile ohne Einzug.</summary>
    Text: string;
    /// <summary>Einzug der Musterzeilen.</summary>
    Indent: string;
    /// <summary>Freie Felder: Zeichen in Text vor der Stelle zwischen den Hochkommas eines leeren Strings.</summary>
    Fields: TArray<Integer>;
  end;

  TAtlasPatternContinuation = class
  public const
    MinLines = 2;
    MaxLines = 5;
  public
    /// <summary>Vorschlag für die leere Zeile ALine (0-basiert) aus den Zeilen darüber; False ohne Muster.
    /// AEnums und AExists dürfen nil sein.</summary>
    class function Suggest(const ALines: TArray<string>; ALine, AMinLines: Integer; const AEnums: TAtlasEnumLookup;
      const AExists: TAtlasNameExists; out ASuggestion: TAtlasPatternSuggestion): Boolean; static;
    /// <summary>Werte eines Aufzählungstyps aus AText, der AMember enthält ("TState = (stA, stB);"); nil ohne.
    /// </summary>
    class function LocalEnumValues(const AText, AMember: string): TArray<string>; static;
    /// <summary>Kommt AName in AText als ganzes Wort vor (Groß-/Kleinschreibung egal)?</summary>
    class function ContainsWord(const AText, AName: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Chars;

type
  {$SCOPEDENUMS ON}
  TTokenKind = (Ident, Number, Str, Symbol, Comment);
  {$SCOPEDENUMS OFF}

  TToken = record
    Kind: TTokenKind;
    Text: string;
    /// <summary>1-basiert in der Zeile.</summary>
    Start: Integer;
    /// <summary>Leerraum davor.</summary>
    Space: string;
  end;

  TTokens = TArray<TToken>;

function LeadingSpace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

function IsOperand(const AToken: TToken): Boolean;
begin
  Result := (AToken.Kind in [TTokenKind.Ident, TTokenKind.Number, TTokenKind.Str]) or
    ((AToken.Kind = TTokenKind.Symbol) and ((AToken.Text = ')') or (AToken.Text = ']')));
end;

function Tokenize(const ALine: string): TTokens;
var
  Index, Start, SpaceStart: Integer;
  Token: TToken;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(ALine) do
  begin
    SpaceStart := Index;
    while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
      Inc(Index);
    if Index > Length(ALine) then
      Break;
    Token := Default(TToken);
    Token.Space := Copy(ALine, SpaceStart, Index - SpaceStart);
    Start := Index;
    Token.Start := Start;
    if TTextChars.IsIdentStart(ALine[Index]) then
    begin
      while (Index <= Length(ALine)) and TTextChars.IsIdentChar(ALine[Index]) do
        Inc(Index);
      Token.Kind := TTokenKind.Ident;
    end
    else if CharInSet(ALine[Index], ['0'..'9']) or ((ALine[Index] = '$') and (Index < Length(ALine)) and
      CharInSet(ALine[Index + 1], ['0'..'9', 'A'..'F', 'a'..'f'])) or ((ALine[Index] = '-') and
      (Index < Length(ALine)) and CharInSet(ALine[Index + 1], ['0'..'9', '$']) and
      ((Length(Result) = 0) or not IsOperand(Result[High(Result)]))) then
    begin
      // Vorzeichen nur, wo kein Operand davorsteht ("A - 1" bleibt eine Rechnung).
      if ALine[Index] = '-' then
        Inc(Index);
      if ALine[Index] = '$' then
      begin
        Inc(Index);
        while (Index <= Length(ALine)) and CharInSet(ALine[Index], ['0'..'9', 'A'..'F', 'a'..'f']) do
          Inc(Index);
      end
      else
        while (Index <= Length(ALine)) and CharInSet(ALine[Index], ['0'..'9']) do
          Inc(Index);
      // Gleitkommazahlen und Bereiche: nur Ganzzahlen bilden Folgen.
      if (Index < Length(ALine)) and (ALine[Index] = '.') and CharInSet(ALine[Index + 1], ['0'..'9']) then
      begin
        Inc(Index);
        while (Index <= Length(ALine)) and CharInSet(ALine[Index], ['0'..'9', 'e', 'E']) do
          Inc(Index);
        Token.Kind := TTokenKind.Symbol;
      end
      else
        Token.Kind := TTokenKind.Number;
    end
    else if ALine[Index] = '''' then
    begin
      Inc(Index);
      while Index <= Length(ALine) do
      begin
        if ALine[Index] = '''' then
        begin
          if (Index < Length(ALine)) and (ALine[Index + 1] = '''') then
            Inc(Index)
          else
            Break;
        end;
        Inc(Index);
      end;
      Inc(Index);
      Token.Kind := TTokenKind.Str;
    end
    else if (ALine[Index] = '/') and (Index < Length(ALine)) and (ALine[Index + 1] = '/') then
    begin
      Index := Length(ALine) + 1;
      Token.Kind := TTokenKind.Comment;
    end
    else if (ALine[Index] = '{') or ((ALine[Index] = '(') and (Index < Length(ALine)) and (ALine[Index + 1] = '*'))
    then
    begin
      if ALine[Index] = '{' then
        Index := Pos('}', ALine, Index)
      else
      begin
        Index := Pos('*)', ALine, Index + 2);
        if Index > 0 then
          Inc(Index);
      end;
      if Index = 0 then
        Index := Length(ALine);
      Inc(Index);
      Token.Kind := TTokenKind.Comment;
    end
    else
    begin
      // Zweizeichige Operatoren als ein Token.
      if (Index < Length(ALine)) and ((Copy(ALine, Index, 2) = ':=') or (Copy(ALine, Index, 2) = '..') or
        (Copy(ALine, Index, 2) = '<=') or (Copy(ALine, Index, 2) = '>=') or (Copy(ALine, Index, 2) = '<>')) then
        Inc(Index);
      Inc(Index);
      Token.Kind := TTokenKind.Symbol;
    end;
    Token.Text := Copy(ALine, Start, Index - Start);
    Result := Result + [Token];
  end;
end;

/// <summary>Gleiche Form: gleiche Länge, gleiche Arten, gleiche Symbole und Kommentare.</summary>
function SameShape(const A, B: TTokens): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then
    Exit;
  for Index := 0 to High(A) do
  begin
    if A[Index].Kind <> B[Index].Kind then
      Exit;
    if (A[Index].Kind in [TTokenKind.Symbol, TTokenKind.Comment]) and (A[Index].Text <> B[Index].Text) then
      Exit;
  end;
  Result := True;
end;

function TryNumber(const AText: string; out AValue: Int64; out AHex: Boolean; out ADigits: Integer): Boolean;
var
  Body: string;
  Negative: Boolean;
begin
  Body := AText;
  Negative := Body.StartsWith('-');
  if Negative then
    Delete(Body, 1, 1);
  AHex := Body.StartsWith('$');
  if AHex then
    Delete(Body, 1, 1);
  ADigits := Length(Body);
  if AHex then
    Result := TryStrToInt64('$' + Body, AValue)
  else
    Result := TryStrToInt64(Body, AValue);
  if Result and Negative then
    AValue := -AValue;
end;

/// <summary>Gleiche Abstände zwischen AValues? ASStep: der Abstand.</summary>
function ConstantStep(const AValues: TArray<Int64>; out AStep: Int64): Boolean;
var
  Index: Integer;
begin
  Result := False;
  AStep := 0;
  if Length(AValues) < 2 then
    Exit;
  AStep := AValues[1] - AValues[0];
  if AStep = 0 then
    Exit;
  for Index := 2 to High(AValues) do
    if AValues[Index] - AValues[Index - 1] <> AStep then
      Exit;
  Result := True;
end;

/// <summary>Zahl wie das Vorbild ATemplate geschrieben: hexadezimal mit gleicher Stellenzahl und Schreibweise.
/// </summary>
function FormatNumber(AValue: Int64; const ATemplate: string; AHex: Boolean; ADigits: Integer): string;
var
  Digits: string;
  Lower: Boolean;
begin
  if not AHex then
    Exit(IntToStr(AValue));
  Digits := IntToHex(Abs(AValue), ADigits);
  Lower := ATemplate <> UpperCase(ATemplate);
  if Lower then
    Digits := LowerCase(Digits);
  Result := '$' + Digits;
  if AValue < 0 then
    Result := '-' + Result;
end;

/// <summary>Bezeichner mit Nummer am Ende: Präfix und Zahl ("Edit12" → "Edit", 12).</summary>
function SplitNumbered(const AName: string; out APrefix: string; out ANumber: Int64; out ADigits: Integer): Boolean;
var
  Index: Integer;
begin
  Index := Length(AName);
  while (Index > 0) and CharInSet(AName[Index], ['0'..'9']) do
    Dec(Index);
  APrefix := Copy(AName, 1, Index);
  ADigits := Length(AName) - Index;
  Result := (Index > 0) and (ADigits > 0) and TryStrToInt64(Copy(AName, Index + 1, MaxInt), ANumber);
end;

/// <summary>Nächster Wert der Spalte AColumn über die Zeilen ATokens; False, wenn keine Folge.</summary>
function NextValue(const ATokens: TArray<TTokens>; const ALineIndexes: TArray<Integer>; AColumn, AIndent: Integer;
  const AEnums: TAtlasEnumLookup; const AExists: TAtlasNameExists; out AValue: string; out AFree: Boolean): Boolean;
var
  Values: TArray<Int64>;
  Texts: TArray<string>;
  Index, Digits, FirstDigits, Position: Integer;
  Value, Step: Int64;
  Hex, FirstHex, Declares, Chars: Boolean;
  Prefix, FirstPrefix, Last: string;
  Members: TArray<string>;

  function MemberIndex(const AName: string): Integer;
  var
    Item: Integer;
  begin
    Result := -1;
    for Item := 0 to High(Members) do
      if SameText(Members[Item], AName) then
        Exit(Item);
  end;

begin
  Result := False;
  AValue := '';
  AFree := False;
  SetLength(Texts, Length(ATokens));
  for Index := 0 to High(ATokens) do
    Texts[Index] := ATokens[Index][AColumn].Text;
  Last := Texts[High(Texts)];
  SetLength(Values, Length(Texts));
  case ATokens[0][AColumn].Kind of
    TTokenKind.Number:
      begin
        FirstHex := False;
        FirstDigits := 0;
        for Index := 0 to High(Texts) do
        begin
          if not TryNumber(Texts[Index], Value, Hex, Digits) then
            Exit;
          if Index = 0 then
          begin
            FirstHex := Hex;
            FirstDigits := Digits;
          end
          else if Hex <> FirstHex then
            Exit;
          Values[Index] := Value;
        end;
        if not ConstantStep(Values, Step) then
          Exit;
        AValue := FormatNumber(Values[High(Values)] + Step, Last, FirstHex, FirstDigits);
        Result := True;
      end;
    TTokenKind.Str:
      begin
        // Einzelne Zeichen mit fester Schrittweite bilden eine Folge, alles andere wird ein freies Feld.
        Chars := True;
        for Index := 0 to High(Texts) do
          if (Length(Texts[Index]) = 3) and (Texts[Index][2] <> '''') then
            Values[Index] := Ord(Texts[Index][2])
          else
            Chars := False;
        if Chars and ConstantStep(Values, Step) and (Values[High(Values)] + Step >= 32) and
          (Values[High(Values)] + Step < $FFFF) and (Values[High(Values)] + Step <> Ord('''')) then
          AValue := '''' + Char(Integer(Values[High(Values)] + Step)) + ''''
        else
        begin
          AValue := '''''';
          AFree := True;
        end;
        Result := True;
      end;
    TTokenKind.Ident:
      begin
        // Nummerierte Bezeichner.
        if SplitNumbered(Texts[0], FirstPrefix, Value, FirstDigits) then
        begin
          Values[0] := Value;
          Index := 1;
          while (Index <= High(Texts)) and SplitNumbered(Texts[Index], Prefix, Value, Digits) and
            SameText(Prefix, FirstPrefix) do
          begin
            Values[Index] := Value;
            Inc(Index);
          end;
          if (Index > High(Texts)) and ConstantStep(Values, Step) and (Values[High(Values)] + Step >= 0) then
          begin
            SplitNumbered(Last, Prefix, Value, Digits);
            AValue := IntToStr(Values[High(Values)] + Step);
            // Führende Nullen wie im Vorbild ("Spalte01").
            while (Length(AValue) < Digits) and (Copy(Last, Length(Prefix) + 1, 1) = '0') do
              AValue := '0' + AValue;
            AValue := Prefix + AValue;
            // Deklariert die Zeile den Namen (Name: Typ; Name, …), darf er neu sein.
            Declares := (AColumn = 0) and (Length(ATokens[0]) > 1) and
              ((ATokens[0][1].Text = ':') or (ATokens[0][1].Text = ','));
            Exit(Declares or (Assigned(AExists) and AExists(AValue)));
          end;
        end;
        // Werte eines Aufzählungstyps.
        if not Assigned(AEnums) then
          Exit;
        Position := AIndent + ATokens[High(ATokens)][AColumn].Start - 1;
        Members := AEnums(Last, ALineIndexes[High(ALineIndexes)], Position);
        if Length(Members) = 0 then
          Exit;
        for Index := 0 to High(Texts) do
        begin
          Values[Index] := MemberIndex(Texts[Index]);
          if Values[Index] < 0 then
            Exit;
        end;
        if not ConstantStep(Values, Step) or (Values[High(Values)] + Step < 0) or
          (Values[High(Values)] + Step > High(Members)) then
          Exit;
        AValue := Members[Values[High(Values)] + Step];
        Result := True;
      end;
  end;
end;

{ TAtlasPatternContinuation }

class function TAtlasPatternContinuation.Suggest(const ALines: TArray<string>; ALine, AMinLines: Integer;
  const AEnums: TAtlasEnumLookup; const AExists: TAtlasNameExists; out ASuggestion: TAtlasPatternSuggestion): Boolean;
var
  Indent, Value: string;
  Run: TArray<TTokens>;
  LineIndexes: TArray<Integer>;
  Tokens, Template: TTokens;
  Line, Column, Index: Integer;
  Varies, Free, AnyVaries: Boolean;
  Builder: TStringBuilder;
begin
  ASuggestion := Default(TAtlasPatternSuggestion);
  Result := False;
  if AMinLines < MinLines then
    AMinLines := MinLines;
  if AMinLines > MaxLines then
    AMinLines := MaxLines;
  if (ALine < AMinLines) or (ALine > High(ALines)) or (Trim(ALines[ALine]) <> '') then
    Exit;
  Indent := LeadingSpace(ALines[ALine - 1]);
  // Längster Lauf gleicher Form direkt über der Cursorzeile, neueste Zeile zuletzt.
  Template := Tokenize(Copy(ALines[ALine - 1], Length(Indent) + 1, MaxInt));
  if Length(Template) = 0 then
    Exit;
  Run := [Template];
  LineIndexes := [ALine - 1];
  Line := ALine - 2;
  while (Line >= 0) and (Length(Run) < MaxLines) and (LeadingSpace(ALines[Line]) = Indent) and
    (Trim(ALines[Line]) <> '') do
  begin
    Tokens := Tokenize(Copy(ALines[Line], Length(Indent) + 1, MaxInt));
    if not SameShape(Tokens, Template) then
      Break;
    Run := [Tokens] + Run;
    LineIndexes := [Line] + LineIndexes;
    Dec(Line);
  end;
  if Length(Run) < AMinLines then
    Exit;
  Builder := TStringBuilder.Create;
  try
    AnyVaries := False;
    for Column := 0 to High(Template) do
    begin
      Varies := False;
      for Index := 1 to High(Run) do
        if Run[Index][Column].Text <> Run[0][Column].Text then
          Varies := True;
      Value := Template[Column].Text;
      Free := False;
      if Varies then
      begin
        if not NextValue(Run, LineIndexes, Column, Length(Indent), AEnums, AExists, Value, Free) then
          Exit;
        if not Free then
          AnyVaries := True;
      end;
      Builder.Append(Template[Column].Space);
      if Free then
        ASuggestion.Fields := ASuggestion.Fields + [Builder.Length + 1];
      Builder.Append(Value);
    end;
    // Nur freie Strings oder lauter gleiche Zeilen sind kein Muster.
    if not AnyVaries then
      Exit;
    ASuggestion.Text := Builder.ToString;
    ASuggestion.Indent := Indent;
    Result := True;
  finally
    Builder.Free;
  end;
end;

class function TAtlasPatternContinuation.ContainsWord(const AText, AName: string): Boolean;
var
  Text, Name: string;
  At: Integer;
begin
  Result := False;
  if AName = '' then
    Exit;
  Text := LowerCase(AText);
  Name := LowerCase(AName);
  At := Pos(Name, Text);
  while At > 0 do
  begin
    if ((At = 1) or not TTextChars.IsIdentChar(Text[At - 1])) and
      ((At + Length(Name) > Length(Text)) or not TTextChars.IsIdentChar(Text[At + Length(Name)])) then
      Exit(True);
    At := Pos(Name, Text, At + 1);
  end;
end;

class function TAtlasPatternContinuation.LocalEnumValues(const AText, AMember: string): TArray<string>;
var
  Text, Name, Inner: string;
  At, Open, Close, Index: Integer;
  Parts: TArray<string>;
  Found: Boolean;
begin
  Result := nil;
  Text := AText;
  Name := LowerCase(AMember);
  // Jede "= ( … )"-Liste aus Bezeichnern ist ein Aufzählungstyp; die mit AMember gewinnt.
  At := Pos('=', Text);
  while At > 0 do
  begin
    Open := At + 1;
    while (Open <= Length(Text)) and CharInSet(Text[Open], [' ', #9, #13, #10]) do
      Inc(Open);
    if (Open <= Length(Text)) and (Text[Open] = '(') and ((Open = Length(Text)) or (Text[Open + 1] <> '*')) then
    begin
      Close := Pos(')', Text, Open);
      if Close = 0 then
        Exit;
      Inner := Copy(Text, Open + 1, Close - Open - 1);
      Parts := Inner.Split([',']);
      Found := False;
      for Index := 0 to High(Parts) do
      begin
        // "stA = 1" erlaubt; nur der Name zählt.
        Parts[Index] := Trim(Parts[Index]);
        if Pos('=', Parts[Index]) > 0 then
          Parts[Index] := Trim(Copy(Parts[Index], 1, Pos('=', Parts[Index]) - 1));
        if (Parts[Index] = '') or not TTextChars.IsIdentStart(Parts[Index][1]) or (Pos(' ', Parts[Index]) > 0) or
          (Pos(':', Parts[Index]) > 0) then
        begin
          Found := False;
          Parts := nil;
          Break;
        end;
        if LowerCase(Parts[Index]) = Name then
          Found := True;
      end;
      if Found then
        Exit(Parts);
    end;
    At := Pos('=', Text, At + 1);
  end;
end;

end.
