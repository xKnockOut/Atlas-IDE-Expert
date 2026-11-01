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
  begin
    Result := A.Character - B.Character;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function Prev(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Next(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Exit;
  end;
  for Word in AWords do
  begin
    if AToken.IsKeyword(Word) then
    begin
      Exit(True);
    end;
  end;
end;

function IsSymbolIn(const AToken: TPascalToken; const ASymbols: array of string): Boolean;
var
  Symbol: string;
begin
  Result := False;
  for Symbol in ASymbols do
  begin
    if AToken.IsSymbol(Symbol) then
    begin
      Exit(True);
    end;
  end;
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
    begin
      Break;
    end;
    if not IsTrivia(ATokens[Index]) then
    begin
      ASlot.NameIndex := Index;
    end;
  end;
  if (ASlot.NameIndex < 0) or (ATokens[ASlot.NameIndex].Kind <> TPascalTokenKind.Identifier) or
    (Compare(APosition, ATokens[ASlot.NameIndex].EndPos) > 0) then
  begin
    Exit;
  end;
  Before := Prev(ATokens, ASlot.NameIndex);
  After := Next(ATokens, ASlot.NameIndex);
  // Mitglied ("X.Name"), Aufruf ("Name(" ist #472), Kette ("Name.X") oder generischer Typ.
  if (Before >= 0) and ATokens[Before].IsSymbol('.') then
  begin
    Exit;
  end;
  if (After <= High(ATokens)) and IsSymbolIn(ATokens[After], ['(', '.', '<', '^']) then
  begin
    Exit;
  end;
  // Inline-Deklaration ("var Name", "var X: Name", "const Name = …").
  Scan := Before;
  while (Scan >= 0) and not EndsStatement(ATokens[Scan]) and
    not IsKeywordIn(ATokens[Scan], ['begin', 'then', 'do', 'try', 'repeat', 'of']) do
  begin
    if IsKeywordIn(ATokens[Scan], ['var', 'const', 'type', 'procedure', 'function', 'property', 'threadvar']) then
    begin
      Exit;
    end;
    Scan := Prev(ATokens, Scan);
  end;
  ASlot.Name := ATokens[ASlot.NameIndex].Text;
  if (ASlot.Name <> '') and (ASlot.Name[1] = '&') then
  begin
    Exit;
  end;
  ASlot.NameRange := TTextRange.Create(ATokens[ASlot.NameIndex].StartPos, ATokens[ASlot.NameIndex].EndPos);
  ASlot.CursorOffset := Max(0, Min(Length(ASlot.Name), APosition.Character - ATokens[ASlot.NameIndex].StartPos.Character));
  if APosition.Line <> ATokens[ASlot.NameIndex].StartPos.Line then
  begin
    ASlot.CursorOffset := Length(ASlot.Name);
  end;
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
      begin
        Inc(Depth);
      end
      else if IsSymbolIn(ATokens[Scan], [')', ']']) then
      begin
        if Depth = 0 then
        begin
          Break;
        end;
        Dec(Depth);
      end
      else if (Depth = 0) and EndsStatement(ATokens[Scan]) then
      begin
        Break;
      end;
      if ASlot.ValueFirst < 0 then
      begin
        ASlot.ValueFirst := Scan;
      end;
      ASlot.ValueLast := Scan;
      Scan := Next(ATokens, Scan);
    end;
  end
  else
  begin
    ASlot.InlineAllowed := False;
  end;
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
    begin
      Inc(Depth);
    end
    else if IsSymbolIn(ATokens[Result], [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
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
    begin
      Comparison := True;
    end;
    if IsSymbolIn(ATokens[Index], ['(', '[']) then
    begin
      Index := Closing(ATokens, Index, ALast);
    end
    else if IsSymbolIn(ATokens[Index], ['=', '<>', '<', '>', '<=', '>=']) or
      IsKeywordIn(ATokens[Index], ['in', 'is']) then
    begin
      Comparison := True;
    end
    else if ATokens[Index].IsSymbol('/') then
    begin
      Divides := True;
    end
    else if IsKeywordIn(ATokens[Index], ['div', 'mod']) then
    begin
      IntegerDivides := True;
    end
    else if ATokens[Index].IsKeyword('as') then
    begin
      AsType := Next(ATokens, Index);
    end;
    Index := Next(ATokens, Index);
  end;
  if Comparison then
  begin
    Exit('Boolean');
  end;
  if (AsType >= 0) and (AsType = ALast) and (ATokens[AsType].Kind = TPascalTokenKind.Identifier) then
  begin
    Exit(ATokens[AsType].Text);
  end;
  if Divides then
  begin
    Exit('Extended');
  end;
  if IntegerDivides then
  begin
    Exit('Integer');
  end;
  // Erster Operand, ohne Vorzeichen und not.
  ATermFirst := AFirst;
  while (ATermFirst < ALast) and (IsSymbolIn(ATokens[ATermFirst], ['-', '+']) or ATokens[ATermFirst].IsKeyword('not')) do
  begin
    ATermFirst := Next(ATokens, ATermFirst);
  end;
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
    begin
      Break;
    end;
    if IsSymbolIn(ATokens[Index], ['(', '[']) then
    begin
      Index := Closing(ATokens, Index, ALast);
    end;
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
      begin
        Result := 'Extended';
      end
      else
      begin
        Result := 'Integer';
      end;
    TPascalTokenKind.StringLiteral:
      if (Length(AToken.Text) = 3) or (AToken.Text = '''''''''') then
      begin
        Result := 'Char';
      end
      else
      begin
        Result := 'string';
      end;
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(AToken.Text, 'True') or SameText(AToken.Text, 'False') then
      begin
        Result := 'Boolean';
      end;
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
  begin
    Exit;
  end;
  // Aufruf am Ende überspringen: "F(x)" hat den Typ von F.
  if ATokens[ALast].IsSymbol(')') then
  begin
    Depth := 0;
    while ALast >= AFirst do
    begin
      if ATokens[ALast].IsSymbol(')') then
      begin
        Inc(Depth);
      end
      else if ATokens[ALast].IsSymbol('(') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Break;
        end;
      end;
      ALast := Prev(ATokens, ALast);
    end;
    ALast := Prev(ATokens, ALast);
  end;
  if (ALast >= AFirst) and (ATokens[ALast].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := ALast;
  end;
end;

class function TDeclareUnknown.UsesFieldPrefix(const AFieldNames: TArray<string>): Boolean;
var
  Name: string;
  Prefixed: Integer;
begin
  Prefixed := 0;
  for Name in AFieldNames do
  begin
    if (Length(Name) >= 2) and (Name[1] = 'F') and CharInSet(Name[2], ['A'..'Z']) then
    begin
      Inc(Prefixed);
    end;
  end;
  Result := 2 * Prefixed >= Length(AFieldNames);
end;

class function TDeclareUnknown.FieldName(const AName: string; APrefix: Boolean): string;
begin
  Result := AName;
  if not APrefix or (AName = '') then
  begin
    Exit;
  end;
  if (Length(AName) >= 2) and (AName[1] = 'F') and CharInSet(AName[2], ['A'..'Z']) then
  begin
    Exit;
  end;
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
  begin
    if SameText(Name, ATypeName) then
    begin
      Exit('0');
    end;
  end;
  for Name in Floats do
  begin
    if SameText(Name, ATypeName) then
    begin
      Exit('0.0');
    end;
  end;
  if SameText(ATypeName, 'string') or SameText(ATypeName, 'UnicodeString') then
  begin
    Exit('''''');
  end;
  if SameText(ATypeName, 'Boolean') then
  begin
    Exit('False');
  end;
  Result := ValuePlaceholder;
end;

class function TDeclareUnknown.WithCaret(const AText: string; AOffset: Integer): string;
begin
  AOffset := Max(0, Min(AOffset, Length(AText)));
  Result := Copy(AText, 1, AOffset) + '$0' + Copy(AText, AOffset + 1, MaxInt);
end;

end.
