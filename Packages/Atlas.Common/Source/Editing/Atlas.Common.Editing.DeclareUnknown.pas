unit Atlas.Common.Editing.DeclareUnknown;

// Unbekannten Bezeichner deklarieren (#471), Teil ohne Namensauflösung:
//   - Slot: getippter Name am Cursor, der eine Variable, ein Feld oder eine Konstante sein kann (kein Punkt
//     davor, kein "(" oder "." dahinter, keine Inline-Deklaration). Ist er Ziel einer Zuweisung, gehört die
//     rechte Seite dazu.
//   - Shape: Form eines Ausdrucks. Vergleiche ergeben Boolean, "/" Extended, div und mod Integer, "as T" den
//     Typ T; sonst entscheidet der erste Operand (TermFirst..TermLast), den der Aufrufer auflöst.
//   - Namen und Platzhalter: Feldname mit F-Konvention, Vorgabewert für Konstanten, "$0" für den Cursor.
// Die Vervollständigung (TLspCompletion.DeclareItems) baut daraus die Einträge; /var aus #294 ist derselbe
// Vorgang als Befehl.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TUnknownSlot = record
    Name: string;
    NameIndex: Integer;
    NameRange: TTextRange;
    /// <summary>Cursor im Namen: Zeichen ab Namensanfang.</summary>
    CursorOffset: Integer;
    /// <summary>"Name := …"; ValueFirst..ValueLast ist dann die rechte Seite (-1, wenn sie fehlt).</summary>
    AssignTarget: Boolean;
    ValueFirst: Integer;
    ValueLast: Integer;
    /// <summary>Der Name beginnt eine Anweisung in einem Block: "var Name := …" ist dort erlaubt.</summary>
    InlineAllowed: Boolean;
  end;

  TDeclareUnknown = class
  public const
    /// <summary>Platzhalter, wenn sich der Typ nicht ableiten lässt; als Kommentar meldet ihn der Compiler.</summary>
    TypePlaceholder = '{Typ}';
    ValuePlaceholder = '{Wert}';
  public
    /// <summary>Name am Cursor, der deklariert werden könnte; False sonst.</summary>
    class function Slot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASlot: TUnknownSlot): Boolean; static;
    /// <summary>Typ aus der Form des Ausdrucks AFirst..ALast; '' heißt: Typ von ATermFirst..ATermLast.</summary>
    class function Shape(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      out ATermFirst, ATermLast: Integer): string; static;
    /// <summary>Typ eines Literals (Zahl, String, Zeichen, True/False); '' sonst.</summary>
    class function LiteralType(const AToken: TPascalToken): string; static;
    /// <summary>Bezeichner, dessen Typ der Term AFirst..ALast hat ("A.B(1).C" → C, "F(x)" → F); -1, wenn er mit
    /// einem Index endet oder keiner ist.</summary>
    class function TermName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer; static;
    /// <summary>Folgen die Felder der Klasse der F-Konvention? Ohne Felder ja (Delphi-Stil).</summary>
    class function UsesFieldPrefix(const AFieldNames: TArray<string>): Boolean; static;
    /// <summary>"TotalCount" → "FTotalCount"; ohne APrefix oder mit schon vorhandenem F unverändert.</summary>
    class function FieldName(const AName: string; APrefix: Boolean): string; static;
    /// <summary>Vorgabewert einer Konstanten vom Typ ATypeName; ValuePlaceholder, wenn unbekannt.</summary>
    class function DefaultValue(const ATypeName: string): string; static;
    /// <summary>AText mit "$0" nach AOffset Zeichen.</summary>
    class function WithCaret(const AText: string; AOffset: Integer): string; static;
  end;

implementation

uses
  System.Math;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function Prev(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

function Next(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
    Exit;
  for Word in AWords do
    if AToken.IsKeyword(Word) then
      Exit(True);
end;

function IsSymbolIn(const AToken: TPascalToken; const ASymbols: array of string): Boolean;
var
  Symbol: string;
begin
  Result := False;
  for Symbol in ASymbols do
    if AToken.IsSymbol(Symbol) then
      Exit(True);
end;

/// <summary>Ende einer Anweisung auf Klammertiefe 0.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['end', 'else', 'until', 'except', 'finally']);
end;

{ TDeclareUnknown }

class function TDeclareUnknown.Slot(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASlot: TUnknownSlot): Boolean;
var
  Index, Before, After, Scan, Depth: Integer;
begin
  ASlot := Default(TUnknownSlot);
  ASlot.ValueFirst := -1;
  ASlot.ValueLast := -1;
  Result := False;
  ASlot.NameIndex := -1;
  for Index := 0 to High(ATokens) do
  begin
    if Compare(ATokens[Index].StartPos, APosition) >= 0 then
      Break;
    if not IsTrivia(ATokens[Index]) then
      ASlot.NameIndex := Index;
  end;
  if (ASlot.NameIndex < 0) or (ATokens[ASlot.NameIndex].Kind <> TPascalTokenKind.Identifier) or
    (Compare(APosition, ATokens[ASlot.NameIndex].EndPos) > 0) then
    Exit;
  Before := Prev(ATokens, ASlot.NameIndex);
  After := Next(ATokens, ASlot.NameIndex);
  // Mitglied ("X.Name"), Aufruf ("Name(" ist #472), Kette ("Name.X") oder generischer Typ.
  if (Before >= 0) and ATokens[Before].IsSymbol('.') then
    Exit;
  if (After <= High(ATokens)) and IsSymbolIn(ATokens[After], ['(', '.', '<', '^']) then
    Exit;
  // Inline-Deklaration ("var Name", "var X: Name", "const Name = …").
  Scan := Before;
  while (Scan >= 0) and not EndsStatement(ATokens[Scan]) and
    not IsKeywordIn(ATokens[Scan], ['begin', 'then', 'do', 'try', 'repeat', 'of']) do
  begin
    if IsKeywordIn(ATokens[Scan], ['var', 'const', 'type', 'procedure', 'function', 'property', 'threadvar']) then
      Exit;
    Scan := Prev(ATokens, Scan);
  end;
  ASlot.Name := ATokens[ASlot.NameIndex].Text;
  if (ASlot.Name <> '') and (ASlot.Name[1] = '&') then
    Exit;
  ASlot.NameRange := TTextRange.Create(ATokens[ASlot.NameIndex].StartPos, ATokens[ASlot.NameIndex].EndPos);
  ASlot.CursorOffset := Max(0, Min(Length(ASlot.Name), APosition.Character - ATokens[ASlot.NameIndex].StartPos.Character));
  if APosition.Line <> ATokens[ASlot.NameIndex].StartPos.Line then
    ASlot.CursorOffset := Length(ASlot.Name);
  ASlot.InlineAllowed := (Before >= 0) and (ATokens[Before].IsSymbol(';') or
    IsKeywordIn(ATokens[Before], ['begin', 'try', 'finally', 'except', 'repeat']));
  if (After <= High(ATokens)) and ATokens[After].IsSymbol(':=') then
  begin
    ASlot.AssignTarget := True;
    // Rechte Seite bis zum Ende der Anweisung.
    Depth := 0;
    Scan := Next(ATokens, After);
    while Scan <= High(ATokens) do
    begin
      if IsSymbolIn(ATokens[Scan], ['(', '[']) then
        Inc(Depth)
      else if IsSymbolIn(ATokens[Scan], [')', ']']) then
      begin
        if Depth = 0 then
          Break;
        Dec(Depth);
      end
      else if (Depth = 0) and EndsStatement(ATokens[Scan]) then
        Break;
      if ASlot.ValueFirst < 0 then
        ASlot.ValueFirst := Scan;
      ASlot.ValueLast := Scan;
      Scan := Next(ATokens, Scan);
    end;
  end
  else
    ASlot.InlineAllowed := False;
  Result := True;
end;

/// <summary>Index der schließenden Klammer zu AIndex ("(" oder "["); ALast, wenn sie fehlt.</summary>
function Closing(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AIndex;
  while Result <= ALast do
  begin
    if IsSymbolIn(ATokens[Result], ['(', '[']) then
      Inc(Depth)
    else if IsSymbolIn(ATokens[Result], [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
    Result := Next(ATokens, Result);
  end;
  Result := ALast;
end;

/// <summary>Binärer Operator.</summary>
function IsOperator(const AToken: TPascalToken): Boolean;
begin
  Result := IsSymbolIn(AToken, ['+', '-', '*', '/', '=', '<>', '<', '>', '<=', '>=']) or
    IsKeywordIn(AToken, ['and', 'or', 'xor', 'div', 'mod', 'shl', 'shr', 'in', 'is', 'as']);
end;

class function TDeclareUnknown.Shape(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out ATermFirst, ATermLast: Integer): string;
var
  Index, AsType, TermFirst, TermLast: Integer;
  Comparison, Divides, IntegerDivides: Boolean;
begin
  Result := '';
  ATermFirst := -1;
  ATermLast := -1;
  if (AFirst < 0) or (ALast < AFirst) then
    Exit;
  Comparison := False;
  Divides := False;
  IntegerDivides := False;
  AsType := -1;
  Index := AFirst;
  while Index <= ALast do
  begin
    // Geklammerter Vergleich ("(A > 1) and B"), aber kein Aufruf ("F(A = B)") und kein Index.
    if ATokens[Index].IsSymbol('(') and ((Index = AFirst) or not ((ATokens[Prev(ATokens, Index)].Kind =
      TPascalTokenKind.Identifier) or IsSymbolIn(ATokens[Prev(ATokens, Index)], [')', ']']))) and
      (Shape(ATokens, Next(ATokens, Index), Prev(ATokens, Closing(ATokens, Index, ALast)), TermFirst,
      TermLast) = 'Boolean') then
      Comparison := True;
    if IsSymbolIn(ATokens[Index], ['(', '[']) then
      Index := Closing(ATokens, Index, ALast)
    else if IsSymbolIn(ATokens[Index], ['=', '<>', '<', '>', '<=', '>=']) or
      IsKeywordIn(ATokens[Index], ['in', 'is']) then
      Comparison := True
    else if ATokens[Index].IsSymbol('/') then
      Divides := True
    else if IsKeywordIn(ATokens[Index], ['div', 'mod']) then
      IntegerDivides := True
    else if ATokens[Index].IsKeyword('as') then
      AsType := Next(ATokens, Index);
    Index := Next(ATokens, Index);
  end;
  if Comparison then
    Exit('Boolean');
  if (AsType >= 0) and (AsType = ALast) and (ATokens[AsType].Kind = TPascalTokenKind.Identifier) then
    Exit(ATokens[AsType].Text);
  if Divides then
    Exit('Extended');
  if IntegerDivides then
    Exit('Integer');
  // Erster Operand, ohne Vorzeichen und not.
  ATermFirst := AFirst;
  while (ATermFirst < ALast) and (IsSymbolIn(ATokens[ATermFirst], ['-', '+']) or ATokens[ATermFirst].IsKeyword('not')) do
    ATermFirst := Next(ATokens, ATermFirst);
  if ATokens[ATermFirst].IsSymbol('@') then
  begin
    ATermFirst := -1;
    Exit('Pointer');
  end;
  ATermLast := ATermFirst;
  Index := ATermFirst;
  while Index <= ALast do
  begin
    if (Index > ATermFirst) and IsOperator(ATokens[Index]) then
      Break;
    if IsSymbolIn(ATokens[Index], ['(', '[']) then
      Index := Closing(ATokens, Index, ALast);
    ATermLast := Index;
    Index := Next(ATokens, Index);
  end;
end;

class function TDeclareUnknown.LiteralType(const AToken: TPascalToken): string;
begin
  Result := '';
  case AToken.Kind of
    TPascalTokenKind.Number:
      if (AToken.Text[1] <> '$') and (AToken.Text[1] <> '%') and
        ((Pos('.', AToken.Text) > 0) or (Pos('e', LowerCase(AToken.Text)) > 0)) then
        Result := 'Extended'
      else
        Result := 'Integer';
    TPascalTokenKind.StringLiteral:
      if (Length(AToken.Text) = 3) or (AToken.Text = '''''''''') then
        Result := 'Char'
      else
        Result := 'string';
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(AToken.Text, 'True') or SameText(AToken.Text, 'False') then
        Result := 'Boolean';
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TDeclareUnknown.TermName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer;
var
  Depth: Integer;
begin
  Result := -1;
  if (AFirst < 0) or (ALast < AFirst) then
    Exit;
  // Aufruf am Ende überspringen: "F(x)" hat den Typ von F.
  if ATokens[ALast].IsSymbol(')') then
  begin
    Depth := 0;
    while ALast >= AFirst do
    begin
      if ATokens[ALast].IsSymbol(')') then
        Inc(Depth)
      else if ATokens[ALast].IsSymbol('(') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Break;
      end;
      ALast := Prev(ATokens, ALast);
    end;
    ALast := Prev(ATokens, ALast);
  end;
  if (ALast >= AFirst) and (ATokens[ALast].Kind = TPascalTokenKind.Identifier) then
    Result := ALast;
end;

class function TDeclareUnknown.UsesFieldPrefix(const AFieldNames: TArray<string>): Boolean;
var
  Name: string;
  Prefixed: Integer;
begin
  Prefixed := 0;
  for Name in AFieldNames do
    if (Length(Name) >= 2) and (Name[1] = 'F') and CharInSet(Name[2], ['A'..'Z']) then
      Inc(Prefixed);
  Result := 2 * Prefixed >= Length(AFieldNames);
end;

class function TDeclareUnknown.FieldName(const AName: string; APrefix: Boolean): string;
begin
  Result := AName;
  if not APrefix or (AName = '') then
    Exit;
  if (Length(AName) >= 2) and (AName[1] = 'F') and CharInSet(AName[2], ['A'..'Z']) then
    Exit;
  Result := 'F' + UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
end;

class function TDeclareUnknown.DefaultValue(const ATypeName: string): string;
const
  Integers: array[0..12] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'LongInt', 'LongWord', 'ShortInt', 'SmallInt', 'Int32');
  Floats: array[0..4] of string = ('Extended', 'Double', 'Single', 'Currency', 'Real');
var
  Name: string;
begin
  for Name in Integers do
    if SameText(Name, ATypeName) then
      Exit('0');
  for Name in Floats do
    if SameText(Name, ATypeName) then
      Exit('0.0');
  if SameText(ATypeName, 'string') or SameText(ATypeName, 'UnicodeString') then
    Exit('''''');
  if SameText(ATypeName, 'Boolean') then
    Exit('False');
  Result := ValuePlaceholder;
end;

class function TDeclareUnknown.WithCaret(const AText: string; AOffset: Integer): string;
begin
  AOffset := Max(0, Min(AOffset, Length(AText)));
  Result := Copy(AText, 1, AOffset) + '$0' + Copy(AText, AOffset + 1, MaxInt);
end;

end.
